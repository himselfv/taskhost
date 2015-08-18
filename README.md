# taskhost.exe #

This is a very simple tool to run command-line tasks hidden and log their output.

I made it to run .cmd scripts as scheduled tasks under current user but without disturbing them.

### What does it do? ###
At a glance:
```
taskhost /o backup.log // backup-www.cmd --hostname 192.168.1.1 --user admin
```

* Runs any arguments you pass to it hidden.
* Logs anything they output.
* Returns the same error code as the child.


### Syntax ###
```
taskhost.exe [/params] [...] // <task> [task params] [...]
```

* `/i <file>` take input from this file
* `/o <file>` redirect output+errors to this file
* `/e <file>` redirect errors to this file.

Note: if you redirect one handle, you have to redirect them all, default input/output will be unavailable and the app may crash if it expects it.

* `/l <file>` log own messages to this file
* `/appid <id>` if i, o, e or l are given in parametrized form here or in config, this will be the parameter (otherwise executable file name)
* `/show` show the window

### Config ###
Some of the settings may be preset in `taskhost.cfg` (or `anyname.cfg` if taskhost is renamed to `anyname.exe`):
```
Log=Logs\taskhost.log
# Use taskhost.log by default if no /l flag is given.
```
Parametrized form can be used. %s will be substituted for the script filename, or for /appid if it's passed on command-line:
```
Output=Logs\%s.log
Error=Logs\%s-errors.log
```
Running `taskhost // backup-www.cmd` will then put logs into `Logs\backup-www.cmd.log` and `Logs\backup-www.cmd-errors.log`. This way you can have one taskhost.exe servicing multiple scripts in a common way.

Supported keys:
```
Log=
Input=
Output=
Error=
```

### Is this related to Windows taskhost.exe? ###

Nope.

### Why did you call it like a Windows one then? ###

Lack of imagination (and there really wasn't a better name).