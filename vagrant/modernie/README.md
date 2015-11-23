# Windows boxes for testing

Based on instructions from https://gist.github.com/andreptb/57e388df5e881937e62a .

## Requirements

* Vagrant
* VirtualBox
* winrm gem installed - `sudo gem install winrm`


## First boot manual setup

Start box with gui enabled:
```
vbgui=1 vagrant up
```

When the machine is booted, do the following steps on VirtualBox guest window:

- Set the [network location](http://windows.microsoft.com/en-us/windows/choosing-network-location#1TC=windows-7) to *Home* or *Work*. Without this the next step **will not work**.
- [Run as an administrator](https://technet.microsoft.com/en-us/library/cc947813%28v=ws.10%29.aspx)  the following script:

```bash
@echo off
set WINRM_EXEC=call %SYSTEMROOT%\System32\winrm
%WINRM_EXEC% quickconfig -q
%WINRM_EXEC% set winrm/config/winrs @{MaxMemoryPerShellMB="300"}
%WINRM_EXEC% set winrm/config @{MaxTimeoutms="1800000"}
%WINRM_EXEC% set winrm/config/client/auth @{Basic="true"}
%WINRM_EXEC% set winrm/config/service @{AllowUnencrypted="true"}
%WINRM_EXEC% set winrm/config/service/auth @{Basic="true"}
```

- At this time the [up command](http://docs.vagrantup.com/v2/cli/up.html) will be probably verifying if the guest booted properly. Since you just configured **WinRM**, the command should terminate successfully.