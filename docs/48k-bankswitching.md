# 48K Bankswitched Games (U3 removed, R7 fitted)

## Overview

A firmware build option, `USE_OE_CTRL=1`, lets VEXTREME run games made of **two 48K banks**: each bank covers
`$0000-$BFFF`, and the Vectrex's PB6 line selects the bank. This is the layout of the "128K" option of
[technobly/vectrex-cartridge](https://github.com/technobly/vectrex-cartridge) (flash A16 = PB6, flash enabled for
everything but `$C000-$FFFF`).

Stock VEXTREME can't do this in firmware alone: U3 (74LVC1G32) enables the data bus buffer U4 only while A15 is low, so
reads of `$8000-$BFFF` never reach the Vectrex. With this option the STM32 drives U4's `/OE` itself, which needs a small
hardware change.

Normal 32K games, 64K PB6 games and the menu keep working on a modified board. A build without the option is unchanged.

## Hardware change (v0.3 and later)

1. **Remove U3** (74LVC1G32, SOT-23-5).
2. **Bridge R7** (0 ohm, normally not fitted) with a short piece of wire. This connects U4 `/OE` to the STM32 (PB8).
   Before removing U3, check that one R7 pad has continuity to U3 pin 4 (the output; on U3's two-pin side, the pin
   that isn't +5V).
3. **Optional:** a pull-up (4.7k-47k) from R7 to 3.3V keeps U4 off during reset and while the UF2 bootloader runs,
   before the firmware drives PB8.

**Without U3, U4 drives the bus into the next cycle; it crashed one Vectrex. See
[U4 /OE Gate Rework](oe-gate-rework.md) for the planned fix (U3 back, gating PB8 with E).**

**A modified board needs the `USE_OE_CTRL=1` firmware.** Any other firmware leaves U4 `/OE` floating, so the cart must
not go into a Vectrex until it's flashed. USB, the drive and DFU do not use U4, so flashing works as usual.

## Building

```
code\build-wsl.cmd -E 1          :: from Windows (see Building on Windows)
make clean all USE_HW=v1.0 USE_UF2=1 USE_OE_CTRL=1
```

## Game files

- Any `.bin` **larger than 64K and up to 128K** is loaded as a 2 x 48K game.
- The first 64K of the file is the bank selected by **PB6 low**, the second 64K the bank selected by **PB6 high** (the
  bank the Vectrex boots in). Each 64K holds `$0000-$FFFF`; `$C000-$FFFF` can't be read by the Vectrex and is ignored.
- Files up to 64K load exactly as before.

## How it works

**RAM, not flash.** The game runs from the STM32's RAM like every other game; nothing is written to internal flash.
96K of game and the 20K menu don't both fit in the 128K of RAM, so they share one 101K area (`c_and_l` in `main.c`):

| Offset | Contents |
|---|---|
| `0x00000-0x07FFF` | PB6 high bank, `$0000-$7FFF` (normal games use `0x00000-0x0FFFF` as before) |
| `0x08000-0x0FFFF` | PB6 low bank, `$0000-$7FFF` |
| `0x10000-0x13FFF` | PB6 high bank, `$8000-$BFFF` |
| `0x14000-0x17FFF` | PB6 low bank, `$8000-$BFFF` |
| `0x14420-0x1941F` | the menu (`menuData`, 20K) |

Only the menu's code (its first `0x3BE0` bytes, up to `MENU_MEM_ADDR`) overlaps the game. The menu's settings, system
data, high score and file list lie above the game and are never touched.

**Loader** (`loadGame48()`): loads the game, except the 15K that overlaps the menu, since the menu is still running.
It computes the CRC over the whole file, as for other games (high score key). Cart RAM (`.ini` options) is disabled
for these games.

- **Game start** (`doStartRom()`): `game48LoadTail()` reads the overlapping 15K from the drive (about 10 ms) and the
  game takes over.
- **Short reset to the menu:** `romemu.S` calls `menu48Restore()`, which copies the menu code back from the copy
  embedded in the firmware (or from `/menu.bin`) and patches in the version, while reset is still held.
- **Long reset to restart the game:** `romemu.S` calls `game48LoadTail()` again, while reset is still held.

**Bus loop** (`romemu.S`):

- `$0000-$7FFF` reads: as before, plus one store that turns U4 on after the byte is on port A.
- `$8000-$BFFF` reads, while a 48K game runs: index `0x10000 + (!PB6 << 14) + A0-A13`.
- `$C000-$FFFF`, writes above `$7FFF`, and the reset vector: U4 off.
- Writes to `$0000-$7FFF`: U4 is turned on to pass the byte to port A, and off again before port A drives.

Unlike U3, the firmware doesn't gate U4 with E. The 6809 latches read data at the end of the cycle, and U4 is turned
off within a loop pass after the address leaves the cart's range.

## Tested

v1.0 board, U3 removed, R7 wired, no pull-up:

- the menu and 32K games
- 64K PB6 games: Y-Music (all songs and pictures)
- a 2 x 48K PB6 game
- a short reset back to the menu (version, settings and file list intact), and a long reset restarting the 48K game

## Limits

- Two banks only (PB6). Four-bank games that also use `/IRQ` as a bank line (e.g. Vectorblade) would need 4 x 48K =
  192K, more than the RAM.
- No cart RAM for 48K games.
- RAM is tight: about 12K is left for the stack.
