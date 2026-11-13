@echo off
rem Builds _LuaXInput.dll for Windower 4: 32-bit, static CRT, linked against
rem Windower's LuaCore.dll through an import library made from luacore.def.
rem
rem   build.cmd                     build\windower\_LuaXInput.dll
rem   build.cmd test <lua-5.1.5\src>
rem                                 that, then a copy linked against a stock
rem                                 Lua 5.1.5 built from the given source, and
rem                                 tests\smoke.lua run with it
rem
rem Needs Visual Studio's C++ tools, found through vswhere.
setlocal

set "ROOT=%~dp0"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo vswhere.exe not found: install Visual Studio with the C++ tools
  exit /b 1
)
rem Through a file rather than for /f: the parentheses in "Program Files (x86)"
rem trip either for's own parser or the cmd /c it runs the command through,
rem whichever way the quotes are laid.
if not exist "%ROOT%build" mkdir "%ROOT%build"
"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%ROOT%build\vs.txt" || exit /b 1
set "VS="
set /p VS=<"%ROOT%build\vs.txt"
if not defined VS (
  echo No Visual Studio with the C++ tools found
  exit /b 1
)
call "%VS%\VC\Auxiliary\Build\vcvarsall.bat" x86 >nul || exit /b 1

set "CFLAGS=/nologo /O2 /W4 /WX /MT /I"%ROOT%include" /I"%ROOT%src""
set "SOURCES="%ROOT%src\luaxinput.c" "%ROOT%src\loader_windows.c""

set "OUT=%ROOT%build\windower"
if not exist "%OUT%" mkdir "%OUT%"
lib /nologo /def:"%ROOT%luacore.def" /machine:x86 /out:"%OUT%\LuaCore.lib" || exit /b 1
cl %CFLAGS% /LD %SOURCES% /Fo"%OUT%\\" /Fe"%OUT%\_LuaXInput.dll" /link "%OUT%\LuaCore.lib" || exit /b 1
echo Built %OUT%\_LuaXInput.dll

if /i not "%~1"=="test" exit /b 0
if "%~2"=="" (
  echo build.cmd test needs the Lua 5.1.5 src directory
  exit /b 1
)

rem Lua 5.1.5 as its own etc\luavs.bat builds it, into the test directory.
set "LUA=%~f2"
set "TEST=%ROOT%build\test"
if not exist "%TEST%\obj" mkdir "%TEST%\obj"
pushd "%LUA%" || exit /b 1
cl /nologo /O2 /W3 /MD /c /DLUA_BUILD_AS_DLL /Fo"%TEST%\obj\\" l*.c || (popd & exit /b 1)
popd
pushd "%TEST%\obj" || exit /b 1
del lua.obj luac.obj
link /nologo /DLL /out:..\lua51.dll l*.obj || (popd & exit /b 1)
cl /nologo /O2 /W3 /MD /c /DLUA_BUILD_AS_DLL "%LUA%\lua.c" || (popd & exit /b 1)
link /nologo /out:..\lua.exe lua.obj ..\lua51.lib || (popd & exit /b 1)
popd

rem Its own object directory: luaxinput.obj and loader_windows.obj would
rem otherwise match the l*.obj that make lua51.dll on the next run.
if not exist "%TEST%\module" mkdir "%TEST%\module"
cl %CFLAGS% /LD %SOURCES% /Fo"%TEST%\module\\" /Fe"%TEST%\_LuaXInput.dll" /link "%TEST%\lua51.lib" || exit /b 1

set "LUA_CPATH=%TEST%\?.dll"
"%TEST%\lua.exe" "%ROOT%tests\smoke.lua" || exit /b 1
