@ECHO OFF
rem build_stage1.bat - assemble and link Stage 1 as a true Windows GUI program.
rem Paths match the Visual Studio and SDK versions used by asm_CSE3120.bat.
setlocal
cd /d "%~dp0"

set "VCBIN=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\HostX86\x86"
set "SDKLIB=C:\Program Files (x86)\Windows Kits\10\lib\10.0.26100.0\um\x86"
set "PATH=%VCBIN%;%PATH%"

ml.exe /c /nologo /coff /W3 /Zi /Fl"stage1.lst" /Fo"stage1.obj" stage1.asm
if errorlevel 1 goto failed

link.exe /NOLOGO /SUBSYSTEM:WINDOWS /MACHINE:X86 /DEBUG /OUT:"stage1.exe" /LIBPATH:"%SDKLIB%" stage1.obj kernel32.lib user32.lib gdi32.lib
if errorlevel 1 goto failed

echo.
echo Build succeeded: stage1.exe
exit /b 0

:failed
echo.
echo Build FAILED - see the first error above.
exit /b 1
