# Building on Windows (WSL, no Docker)

`code/build-wsl.sh` builds the VEXTREME menu and STM32 firmware in WSL with the same toolchain the Docker
images use, without Docker. It reproduces the official v0.40 release (`stm32-sw.v0.40.hw.v0.3-64kbankfix.bin`)
byte for byte.

## Requirements

- WSL with Ubuntu (`wsl --install -d Ubuntu`). The first build installs a few packages with `sudo apt-get`
  and downloads the toolchain into `~/vx` inside WSL (about 500 MB).

## Building

From a Windows command prompt or PowerShell, in the repo:

```
code\build-wsl.cmd                 :: v1.0 hardware, UF2 layout, last commit
code\build-wsl.cmd -H v0.3 -U 0    :: v0.3 hardware, plain image for 0x08000000
code\build-wsl.cmd -r v0.40        :: a tag, branch or commit
```

Or from WSL: `code/build-wsl.sh` with the same options.

| Option | Default | Meaning |
|---|---|---|
| `-r` | `HEAD` | commit, branch or tag to build. Uncommitted changes are not built. |
| `-H` | `v1.0` | hardware: `v0.2`, `v0.3`, `v0.4`, `v1.0` |
| `-U` | `1` | `1`: UF2 layout (app at `0x08004000`, needs the UF2 bootloader). `0`: plain image at `0x08000000`. |
| `-o` | `build/<sw>-hw<hw>[-uf2]-<sha>/` | output folder |

The output folder gets `VEXTREME.uf2` (UF2 builds), the `.bin`, `.elf`, `.map` and the `menu.bin` built
into it. For flashing, see [Firmware Updates](firmware-updates.md) and the README.

## Why not Docker or a newer compiler

- **Line endings:** Git for Windows defaults to `core.autocrlf=true`, which checks the Makefiles and scripts
  out with CRLF line endings; `make` and `bash` in a Linux container then fail with confusing errors. The script
  clones the repo inside WSL, so the build always sees LF.
- **Toolchain:** it uses `gcc-arm-none-eabi 10-2020-q4`, the version `code/stm32/Dockerfile` pins. Newer
  `arm-none-eabi` toolchains (e.g. Ubuntu's GCC 13) link without errors but put the embedded menu (the second
  `.text` block in `stm32f411rct6-uf2.ld`) in RAM instead of flash: the `.bin` grows to ~400 MB and the firmware
  has no menu. The script stops if the image is bigger than the flash or the menu is missing.
- **asm6809** has no Ubuntu package; the script builds version 2.16 from source.
