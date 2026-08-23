@echo off
rem  Makefile.bat -- the Makefile's targets, from a cmd.exe prompt.
rem
rem  Three doors into the same house. `make` is the entry point on macOS,
rem  `build.ps1` is the one on Windows, and this is for the prompt that has
rem  neither: hands that type `make install` and a shell with no make in it.
rem  Every target is forwarded to build.ps1 rather than reimplemented, so there
rem  is one description of what `install` means and not two that drift apart.
rem
rem      Makefile.bat                      the list of targets
rem      Makefile.bat install              release build into %LOCALAPPDATA%
rem      Makefile.bat clean distclean      several targets, left to right
rem      Makefile.bat build CONFIG=debug   make-style variables
rem      Makefile.bat run MODULE="Examples\Happy Hour.med"
rem
rem  Variables: CONFIG=debug|release, MODULE=<file>, PREFIX=<directory>.
rem  INSTALL_DIR is taken as well, because that is what the Makefile calls it.
rem  A value with spaces in it has to be quoted, the same as it does for make.

setlocal EnableDelayedExpansion

rem  Kept whole, because %1 will not be: it is the only place the equals sign
rem  survives, and so the only way to tell a misspelt variable from a target.
set "COMMANDLINE=%*"

set "SCRIPT=%~dp0build.ps1"
if not exist "%SCRIPT%" (
    echo Makefile.bat: build.ps1 is not next to this file; nothing to forward to. 1>&2
    exit /b 1
)

rem  Windows PowerShell is on every Windows and is what build.ps1 was written
rem  against; pwsh is only there if somebody installed it, and will do.
set "SHELL_EXE="
for %%P in (powershell.exe pwsh.exe) do (
    if not defined SHELL_EXE if not "%%~$PATH:P"=="" set "SHELL_EXE=%%~$PATH:P"
)
if not defined SHELL_EXE (
    echo Makefile.bat: no PowerShell on PATH. 1>&2
    exit /b 1
)

set "TARGETS="
set "OPT_Config="
set "OPT_Module="
set "OPT_Prefix="

rem  cmd.exe breaks a batch file's arguments apart at equals signs as well as at
rem  spaces, so `CONFIG=debug` never arrives as one argument: %1 is CONFIG and
rem  %2 is debug. That is why a variable is recognised by its name and then
rem  takes whatever came next, rather than being split here -- there is nothing
rem  left to split. It also means `CONFIG debug` works, which is harmless.
:parse
if "%~1"=="" goto dispatch
set "ARG=%~1"

set "PARAMETER="
if /i "!ARG!"=="CONFIG"      set "PARAMETER=Config"
if /i "!ARG!"=="MODULE"      set "PARAMETER=Module"
if /i "!ARG!"=="PREFIX"      set "PARAMETER=Prefix"
if /i "!ARG!"=="INSTALL_DIR" set "PARAMETER=Prefix"

if not defined PARAMETER (
    rem  Written with an equals sign after it, so it was meant as a variable
    rem  and not as a target. Saying which is kinder than letting it arrive at
    rem  build.ps1 as a task nobody has heard of.
    echo !COMMANDLINE!| findstr /i /c:"!ARG!=" >nul 2>&1
    rem  Out of the block to say so, rather than nested inside it: an `exit /b`
    rem  two blocks deep and downstream of a pipe leaves the code behind.
    if not errorlevel 1 goto novariable
    set "TARGETS=!TARGETS! !ARG!"
    shift
    goto parse
)

if "%~2"=="" (
    echo Makefile.bat: !ARG! needs a value, as !ARG!=something. 1>&2
    exit /b 1
)
set "OPT_!PARAMETER!=%~2"
shift
shift
goto parse

:dispatch
rem  The Makefile's default goal is help, and a bare `make` should not start
rem  building things nobody asked for.
if not defined TARGETS (
    call :usage
    set "TARGETS=help"
)

for %%T in (%TARGETS%) do (
    call :invoke %%T
    if errorlevel 1 exit /b 1
)
exit /b 0

:invoke
set "ARGS=%~1"
if defined OPT_Config set "ARGS=%ARGS% -Config "%OPT_Config%""
if defined OPT_Module set "ARGS=%ARGS% -Module "%OPT_Module%""
if defined OPT_Prefix set "ARGS=%ARGS% -Prefix "%OPT_Prefix%""
"%SHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %ARGS%
exit /b %ERRORLEVEL%

rem  Only the calling convention, which is the one thing build.ps1 cannot say
rem  from here. The list of targets is its to print, so there is one of those.
:usage
echo Makefile.bat ^<target^>... [CONFIG=debug^|release] [MODULE=^<file^>] [PREFIX=^<directory^>]
echo.
exit /b 0

:novariable
echo Makefile.bat: there is no variable called %ARG%. 1>&2
echo   CONFIG, MODULE and PREFIX are the ones there are. 1>&2
exit /b 1
