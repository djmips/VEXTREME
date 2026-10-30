@echo off
rem Build VEXTREME in WSL from Windows. Options are passed to build-wsl.sh, e.g.:
rem   code\build-wsl.cmd                 v1.0 hardware, UF2 layout, HEAD
rem   code\build-wsl.cmd -H v0.3 -U 0    v0.3 hardware, plain image at 0x08000000
rem   code\build-wsl.cmd -r v0.40        build a tag or commit
rem Uses the default WSL distribution; set VX_WSL_DISTRO to choose another (e.g. Ubuntu).
setlocal
set "SCRIPT=%~dp0build-wsl.sh"
for /f "usebackq delims=" %%P in (`wsl wslpath -a "%SCRIPT%"`) do set "WSLSCRIPT=%%P"
if defined VX_WSL_DISTRO (
    wsl -d %VX_WSL_DISTRO% -- bash "%WSLSCRIPT%" %*
) else (
    wsl -- bash "%WSLSCRIPT%" %*
)
