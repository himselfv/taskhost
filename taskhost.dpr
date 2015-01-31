program taskhost;
{ Runs command-line scripts in a hidden window with input-output redirected }

{$R *.res}

uses
  SysUtils, Classes, Windows;

const
  LL_DEBUG = 0;
  LL_UI = 1;

var
  OwnOutput: string = '';

procedure Log(AMessage: string; ALevel: integer = LL_DEBUG);
var hLog: THandle;
  bytesWritten: cardinal;
begin
  if OwnOutput='' then begin
    if ALevel = LL_UI then
      MessageBox(0, PChar(AMessage), PChar('taskhost'), MB_OK);
    exit;
  end;

  AMessage := '['+DatetimeToStr(now())+' '+IntToStr(GetTickCount) + '] '+AMessage+#13#10;
  hLog := CreateFile(PChar(OwnOutput), GENERIC_WRITE, FILE_SHARE_WRITE, nil, OPEN_ALWAYS, 0, 0);
  if hLog=INVALID_HANDLE_VALUE then
    exit; //can't help!

  SetFilePointer(hLog, 0, nil, FILE_END);
  WriteFile(hLog, AMessage[1], Length(AMessage)*SizeOf(AMessage[1]), bytesWritten, nil);

  CloseHandle(hLog);
end;


type
  EBadUsage = class(Exception);

procedure BadUsage(const AMessage: string = '');
begin
  raise EBadUsage.Create(AMessage);
end;

procedure ShowUsage(const AMessage: string = '');
var msg: string;
begin
  if AMessage<>'' then
    msg := AMessage + #13#10#13#10
  else
    msg := '';

  msg := msg
    + 'Runs a command-line application or script hidden.'#13#10
    + 'Usage: '+ExtractFilename(ParamStr(0))+' [/params] [...] // <task> [task params] [...]'#13#10
    + 'Params:'#13#10
    + 'Input redirection:'#13#10
    + '  /i <file>     take input from this file'#13#10
    + '  /o <file>     redirect output+errors to this file'#13#10
    + '  /e <file>     redirect errors to this file'#13#10
    + '   Note: if you redirect one handle, you have to redirect them all, '
      + 'default input/output will be unavailable and the app may crash if it expects it.'#13#10
    + '  /l <file>     log operations to this file'#13
    + '  /appid <id>   if i, o, e or l are given in parametrized form here or in '
      +'config, this will be the parameter (otherwise exec. file name)'#13
    + '  /show         show the window';

  Log(msg, LL_UI);
end;

//Takes a clean command-line parameter and escapes it so that it can be joined
//with others:
//   param1, param 2, param 3    -->    param1 "param 2" "param 3"
function EscapeParam(pm: string): string;
var i: integer;
begin
  if (pos(' ', pm)<=0) and (pos('"', pm)<=0) then begin
    Result := pm;
    exit;
  end;

  Result := '';
  for i := 1 to Length(pm) do begin
    if pm[i]='\' then
      Result := Result + '\\'
    else
    if pm[i]='"' then
      Result := Result + '\"'
    else
      Result := Result + pm[i];
  end;
  Result := '"' + Result + '"';
end;

//Takes AppID (any string, perhaps a path) and replaces any reserved characters,
//making it a valid filename, filename component or relative path + filename,
//but not absolute path.
//If subdirs is False, also merges path components
//E.g. C:\Pics\file.exe  ->   C__Pics_File.exe     (Subdirs=false)
//                       ->   C_\Pics\File.exe     (Subdirs=true)
function NormalizeAppID(id: string; subdirs: boolean = false): string;
var i: integer;
begin
  Result := '';
  for i := 1 to Length(id) do
    if (Ord(id[i])<32)
    or (pos(id[i], '<>:"|?*')>0) then
      Result := Result + '_'
    else
    if (id[i]='/') or (id[i]='\') then
      if Subdirs then
        Result := Result + '\' //also normalize
      else
        Result := Result + '_'
    else
      Result := Result + id[i];
end;

var
  ChildApp: string = ''; //not escaped
  ChildCommandLine: string = ''; //params escaped
  AppID: string = '';
  RedirectInput: string = '';
  RedirectOutput: string = '';
  RedirectError: string = '';
  ShowWindow: boolean = false;

procedure ParseConfig();
var cfg: TStringList;
begin
  cfg := TStringList.Create;
  try
    try
      cfg.LoadFromFile(ChangeFileExt(Paramstr(0), '.cfg'));
      OwnOutput := cfg.Values['Log'];
      RedirectInput := cfg.Values['Input'];
      RedirectOutput := cfg.Values['Output'];
      if cfg.IndexOfName('Error')>=0 then
        RedirectError := cfg.Values['Error']
      else
        RedirectError := RedirectOutput;
    except
      on E: EFOpenError do
        exit;
    end;
  finally
    FreeAndNil(cfg);
  end;
end;

procedure ParseCommandLine();
var i: integer;
  s: string;
begin
  if ParamCount<1 then
    BadUsage();

  i := 1;
  while i<=ParamCount() do begin
    s := ParamStr(i);

    if s='/appid' then begin
      Inc(i);
      if i>ParamCount() then
        BadUsage('/appid: id missing');
      AppID := NormalizeAppID(ParamStr(i));
    end else
    if s='/i' then begin
      Inc(i);
      if i>ParamCount() then
        BadUsage('/i: filename missing');
      RedirectInput := ParamStr(i);
    end else
    if s='/l' then begin
      Inc(i);
      if i>ParamCount() then
        BadUsage('/l: filename missing');
      OwnOutput := ParamStr(i);
    end else
    if s='/o' then begin
      Inc(i);
      if i>ParamCount() then
        BadUsage('/o: filename missing');
      RedirectOutput := ParamStr(i);
      RedirectError := RedirectOutput;
    end else
    if s='/e' then begin
      Inc(i);
      if i>ParamCount() then
        BadUsage('/e: filename missing');
      RedirectError := ParamStr(i);
    end else
    if s='/show' then begin
      ShowWindow := true;
    end else
    if s='//' then begin
      Inc(i);
      break; //rest goes to ChildCommandLine
    end else
      BadUsage('Unrecognized parameter: '+s);

    Inc(i);
  end;

 //Rest of the params goes to ChildCommandLine
  while i<=ParamCount() do begin
    s := ParamStr(i);
    if ChildApp='' then
      ChildApp := s //don't EscapeParam back the command itself
    else
    if ChildCommandLine='' then
      ChildCommandLine := EscapeParam(s)
    else
      ChildCommandLine := ChildCommandLine + ' ' + EscapeParam(s);
    Inc(i);
  end;
end;


//Same as normal ForceDirectories but also handles relative paths (empty dir names)
function ForceDirectories(Dir: string): Boolean;
begin
  Result := True;
  if Dir = '' then begin
    Result := true;
    exit;
  end;

  Dir := ExcludeTrailingPathDelimiter(Dir);
  if DirectoryExists(Dir) then
    Exit;

  if (Length(Dir) < 3) or (ExtractFilePath(Dir) = Dir) then
    Result := CreateDir(Dir)
  else
    Result := ForceDirectories(ExtractFilePath(Dir)) and CreateDir(Dir);
end;

function SystemDirectory: string;
var
  dir: array [0..MAX_PATH] of Char;
begin
  GetSystemDirectory(dir, MAX_PATH);
  Result := StrPas(dir);
end;

procedure Run();
var
  ChildAppExt: string;
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  hInput, hOutput, hError: THandle;
  WorkDir: string;
  AExitCode: cardinal;
begin
  if ChildApp='' then
    BadUsage('No child command line given');

  if AppID='' then
    AppID := NormalizeAppID(ExtractFilename(ChildApp)); //can't have drive letter in log names

 //Update file names to reflect known child app
  RedirectInput := Format(RedirectInput, [AppID]);
  RedirectOutput := Format(RedirectOutput, [AppID]);
  RedirectError := Format(RedirectError, [AppID]);
  OwnOutput := Format(OwnOutput, [AppID]);
 //Force directories if needed
  if RedirectOutput<>'' then ForceDirectories(ExtractFilePath(RedirectOutput));
  if RedirectError<>'' then ForceDirectories(ExtractFilePath(RedirectError));
  if OwnOutput<>'' then ForceDirectories(ExtractFilePath(OwnOutput));
  Log('Starting <'+ChildApp+'> '+ChildCommandLine+'...');

  with SA do begin
    nLength := SizeOf(SA);
    bInheritHandle := True;
    lpSecurityDescriptor := nil;
  end;

  if RedirectInput<>'' then begin
    hInput := CreateFile(PChar(RedirectInput), GENERIC_READ, FILE_SHARE_READ, @SA, OPEN_EXISTING, 0, 0);
    if hInput=INVALID_HANDLE_VALUE then
      RaiseLastOsError();
  end else
    hInput := 0;

  if RedirectOutput<>'' then begin
    hOutput := CreateFile(PChar(RedirectOutput), GENERIC_WRITE, FILE_SHARE_READ, @SA, OPEN_ALWAYS, 0, 0);
    if hOutput=INVALID_HANDLE_VALUE then
      RaiseLastOsError();
    if GetLastError()=ERROR_ALREADY_EXISTS then
      SetFilePointer(hOutput, 0, nil, FILE_END);
  end else
    hOutput := 0;

  if RedirectError<>'' then begin
    if RedirectError=RedirectOutput then
      hError := hOutput
    else begin
      hError := CreateFile(PChar(RedirectError), GENERIC_WRITE, FILE_SHARE_READ, @SA, OPEN_ALWAYS, 0, 0);
      if hError=INVALID_HANDLE_VALUE then
        RaiseLastOsError();
      if GetLastError()=ERROR_ALREADY_EXISTS then
        SetFilePointer(hError, 0, nil, FILE_END);
    end;
  end else
    hError := 0;

  try
    with SI do begin
      FillChar(SI, SizeOf(SI), 0);
      cb := SizeOf(SI);
      dwFlags := STARTF_USESHOWWINDOW;
      if (RedirectInput<>'') or (RedirectOutput<>'') or (RedirectError<>'') then
        dwFlags := dwFlags or STARTF_USESTDHANDLES;
      if ShowWindow then
        wShowWindow := SW_SHOW
      else
        wShowWindow := SW_HIDE;
      hStdInput := hInput;
      hStdOutput := hOutput;
      hStdError := hError;
    end;

    WorkDir := GetCurrentDir();

    ChildAppExt := ExtractFileExt(ChildApp).ToLower;
    if (ChildAppExt='.cmd') or (ChildAppExt='.bat') then begin
      if ChildCommandLine<>'' then
        ChildCommandLine := '/C '+ChildApp + ' ' + ChildCommandLine
      else
        ChildCommandLine := '/C '+ChildApp;
      ChildApp := SystemDirectory()+'\cmd.exe';
    end;

    if not CreateProcess(
      PChar(ChildApp), PChar(EscapeParam(ChildApp)+' '+ChildCommandLine),
      nil, nil, True, 0, nil,
      PChar(WorkDir), SI, PI) then
      RaiseLastOsError();

    if hInput<>0 then
      CloseHandle(hInput);
    if hOutput<>0 then
      CloseHandle(hOutput);
    if (hError<>0) and (hError<>hOutput) then
      CloseHandle(hError);

    try
      if WaitForSingleObject(PI.hProcess, INFINITE)<>WAIT_OBJECT_0 then
        raise Exception.Create('Unexpected result from WaitForSingleObject!');
      if not GetExitCodeProcess(PI.hProcess, AExitCode) then
        RaiseLastOsError();
      Log(ExtractFilename(ChildApp)+' finished with exit code '+IntToStr(AExitCode));
      System.ExitCode := AExitCode;
    finally
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
    end;

  finally
  end;
end;

begin
  try
    ParseConfig();
    ParseCommandLine();
    Run();
  except
    on E: EBadUsage do begin
      ShowUsage(E.Message);
      System.ExitCode := -1
    end;
    on E: Exception do begin
      Log(E.ClassName+': '+E.Message, LL_UI);
      System.ExitCode := -1;
    end;
  end;
end.
