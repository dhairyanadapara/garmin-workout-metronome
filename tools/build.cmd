@echo off
setlocal enabledelayedexpansion
rem Windows wrapper for build.sh, so the build works from cmd.exe / Cmder /
rem PowerShell as well as from a bash shell.
rem
rem   tools\build.cmd sim        build AND run in the simulator
rem   tools\build.cmd test       build AND run the unit tests
rem   tools\build.cmd device     build the .prg to sideload onto the watch
rem   tools\build.cmd spike      build AND run the Phase 1 hardware probe
rem   tools\build.cmd release    build the signed .iq for the store
rem
rem Running "build.sh" directly from cmd.exe just makes Windows ask which app
rem should OPEN the file, because .sh is not an executable type there.

set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe"      set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not defined BASH_EXE (
    echo Could not find Git Bash ^(bash.exe^).
    echo Install Git for Windows from https://git-scm.com/download/win
    exit /b 1
)

"%BASH_EXE%" "%~dp0build.sh" %*
exit /b %ERRORLEVEL%
