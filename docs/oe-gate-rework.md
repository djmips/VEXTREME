# U4 /OE Gate Rework (planned, not done yet)

Status, 2026-11-04: **planned**. djmips's cart (v1.0, U3 removed, R7 bridged) is kept out of every Vectrex until this
rework is done.

## Why

The [48K bankswitching](48k-bankswitching.md) mod removes U3 and lets the STM32 drive U4 `/OE` directly (PB8 through
R7). U3 had gated U4 with the Vectrex's `/OE` (E), so U4 stopped driving at the end of every bus cycle. With U3 gone,
U4 keeps driving until the firmware's polling loop notices the next address. If that next cycle is a Vectrex RAM, VIA
or BIOS read, both sides drive the data bus for a moment.

What happened:

- **Taiwan unit (107008A):** everything works: the menu, 32K games, Y-Music, 2 x 48K games, The Robots (2 x 64K).
- **HK GCE unit (105524):** after the Vectrex title and the VEXTREME boot screen, the menu starts to draw, then the
  screen goes black. Other carts (Armor Attack, Space Wars, UVMC2) worked in it. Both the RAM build (5d77264) and the
  flash build (0167beb) crashed.
- **Test v1** (U4 off at E fall, below) brought the menu up in the HK unit, but corrupted: missing letters, wrong
  vectors. That's the stale-address bug fixed in test v2, which was built but never run.
- The HK GCE unit then went black in the menu and **stays dead**, with or without a cart. It was probably borderline
  anyway, but the cart may have contributed.

## The rework: U3 back as a gate on PB8 and /OE

The result is U4 `/OE` = PB8 OR Vectrex `/OE`. U4 can only drive inside E high of a cycle the firmware has claimed,
and the hardware ends every drive at E fall. `$8000-$BFFF` stays possible, because the firmware, not A15, decides
which cycles are ours.

The original U3 (74LVC1G32) is reused, **powered from 3.3V instead of 5V**.

### Nets (v1.0 board files, hw-v1.0-a9cfe15)

| Part / pin | Net | Goes to |
|---|---|---|
| U3 pin 1 (input A) | V-CE | STM32 pin 36 = PB15 (A15) |
| U3 pin 2 (input B) | V-OE | STM32 pin 29 = PB10 (Vectrex /OE, i.e. /E) |
| U3 pin 3 | GND | |
| U3 pin 4 (output Y) | R7 pad 1 | U4 (SN74LVC8T245) pin 22, /OE |
| U3 pin 5 | +5V | |
| R7 pad 2 | | STM32 pin 61 = PB8 |
| C3 pad 1 | +3V3 | 0805 capacitor about 7 mm from U3, the nearest easy 3.3V point |

Everything is on the component side, the "THIS SIDE DOWN" side. SOT-23-5: pins 1, 2, 3 on one long side, 4 and 5 on
the other; pin 5 is opposite pin 1.

### Steps

1. Bend **pins 1 and 5** of U3 up so they don't touch their pads. Pin 1's pad (A15) and pin 5's pad (+5V) stay
   unconnected.
2. Solder pins 2, 3 and 4 to their pads as normal.
3. Remove the Kynar bridge from **R7**.
4. Kynar from **pin 1 to R7 pad 2** (the PB8 side).
5. Kynar from **pin 5 to C3 pad 1** (+3V3). Measure first: 3.3V against GND, with the cart on USB.
6. Optional, recommended: any resistor, 4.7k-47k, **from pin 1 to pin 5** (PB8 pull-up to 3.3V). It keeps U4 off from
   power-on through the UF2 bootloader, before the firmware drives PB8.

### Checks before it goes into a Vectrex (USB only)

- Pin 5 is at 3.3V.
- No short from pin 1 or pin 5 to their old pads.
- R7 pad 1 to U3 pin 4: continuity. R7 pad 2 to U3 pin 1: continuity.
- R7 pad 1 to R7 pad 2: **no** continuity.
- Flash the matching firmware (below), then test in the **Taiwan unit first**, then the HK MB unit.

### Why 3.3V for U3

74LVC input thresholds follow the supply: at 5V a high must be at least 3.5V (0.7 x VCC), at 3.3V only 2.0V. The
Vectrex's signals are NMOS/TTL: the 6809 guarantees 2.4V for a high, 74LS parts 2.7V. So on a **stock** board, U3 at
5V is fed levels below its specified high threshold. It works in practice because lightly loaded lines rise higher,
but a weak console can leave an input between the thresholds, where the output is undefined. PB8 (3.3V) would sit right
at that edge.

At 3.3V:

- the thresholds are TTL-compatible;
- LVC inputs tolerate 5V even at a 3.3V supply;
- the output matches U4's /OE, which is referenced to U4's 3.3V side (VCCA, pin 1).

For a board respin: power U3 from 3.3V, or use a 74AHCT1G32 (TTL thresholds at 5V).

If one is ever needed, the replacement part is **SN74AHCT1G32DBVR** or **74AHCT1G32GV** (SOT-23-5; the GW suffix is the
smaller SOT-353 and won't fit). At 5V it reads PB8 fine, so pin 5 could stay on its pad; only pin 1 is lifted.

## Firmware for the reworked board

The gate ends every drive at E fall. If the next cycle isn't ours, the firmware must still release PB8 before E rises
again, and today's loop (5d77264) only releases it once it notices the new address, which is close to that limit.
Planned: an `OE_GATE` build option (or a change to `USE_OE_CTRL`) with the change below.

- **U4 on early:** at the start of `readbyte`, before the byte is fetched. Port A briefly shows the previous byte,
  which is harmless, since the CPU only latches at E fall.
- **Release at E fall:** wait for E high, then for E low, then turn U4 off.
- **Watch for a stale address:** while waiting for E high, keep checking the address pins. Right after E falls the
  loop can still see the previous cycle's address. If the address changes before E rises, serve the new one. Test v1
  didn't do this: it waited a whole cycle on the old address and fed the CPU the previous byte, which corrupted the
  menu.

Test v2, against 5d77264 (built as `build/test-egate2/`, MD5 43d4a561004c3fccedf16ca378896f48, **never run on
hardware**). PB10 low = E high. r9 is free in the read path (the write path already uses it as scratch and returns via
`initloop`, which reloads it).

```diff
--- a/code/stm32/romemu.S
+++ b/code/stm32/romemu.S
@@ -222,8 +222,8 @@
     // Handle read: load address, get byte, send to Vectrex
-    ldr   r0,[r1, 0x10]         // Load addr pins
-    eor   r0, r0, #0x8000       // PB6 is inverted here, this makes handling the menu a bit easier.
+    ldr   r9,[r1, 0x10]         // Load addr pins (r9 keeps them raw, readbyte watches for a change)
+    eor   r0, r9, #0x8000       // PB6 is inverted here, this makes handling the menu a bit easier.
@@ -233,11 +233,25 @@
 readbyte:
+#if OE_CTRL
+    str   r11,[r4, 0x18]        // U4 on early (as U3 did at E rise); the CPU only latches at E fall
+#endif
     ldrb  r5,[r0, r2]           // Load corresponding byte in rom
     orr.w r5,r5,#0xff0000       // Set shit (this clears 0-7, but then the set register overrides the cleared bits)
     str   r5,[r3, 0x18]         // Output
 #if OE_CTRL
-    str   r11,[r4, 0x18]        // U4 on: drive the byte onto the Vectrex data bus
+1:  ldr   r6,[r4, 0x10]         // Wait for E high (/E, PB10, low)
+    lsls  r6,#(31-10)           // |
+    bpl   2f                    // |
+    ldr   r6,[r1, 0x10]         // E still low: has the address changed? Then this was the
+    cmp   r6,r9                 // | previous cycle's address, seen again just after E fell:
+    beq   1b                    // | serve the new one (U4 stays on, wloop decides)
+    b     wloop                 // |
+2:  ldr   r6,[r4, 0x10]         // Wait for E low again (/E high): the CPU has latched the byte
+    lsls  r6,#(31-10)           // |
+    bpl   2b                    // |
+    str   r12,[r4, 0x18]        // U4 off
 #endif
@@ -252,6 +266,7 @@
     ldr   r5,[r1, 0x10]         // Load addr pins (A0-A14, PB6)
+    mov   r9,r5                 // | raw, for readbyte
```

Known gap: an address change only in A15 (the same low 15 bits, PB6 unchanged) isn't seen by the stale-address check,
because A15 is on GPIOB, not GPIOC. It's rare. With the hardware gate in place it can only cost one wrong byte, not a
bus collision.

To build a test without committing: run `code/build-wsl.sh -E 1` for the base commit, copy the patched `romemu.S`
into `~/vx/build-src/code/stm32/` (LF line endings), put `~/vx/gcc10/bin` first on PATH, and run
`make images USE_HW=v1.0 USE_UF2=1 USE_OE_CTRL=1 TOOLCHAIN_DIR=$HOME/vx/libopencm3` there.

## Cart state and backups

- On the cart now: **test v1** (U4 off at E fall, without the stale-address check). Don't run it.
- Backups of the cart's whole internal flash, in `E:\projects\vextreme-cart-backups\2026-11-03\`:
  - `flash-before.bin`: the RAM build (5d77264, `-E 1`), known good in the Taiwan unit;
  - `flash-before-egate.bin`: the flash build (0167beb, `-E 1`);
  - `flash-after-egate.bin`: test v1.
- Restore: DFU mode (hold SW1 while plugging in USB), then
  `dfu-util -a 0 -d 0483:df11 -s 0x08004000 -D <app>.bin`, where `<app>.bin` is the image from offset 0x4000 (or the
  matching `build\...\VEXTREME.bin`). Verify by reading back with `-U`.
