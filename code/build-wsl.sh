#!/bin/bash
#
# Build the VEXTREME menu and STM32 firmware under WSL (or any Linux), without Docker.
#
# Usage (from the repo, in WSL):
#   code/build-wsl.sh [-r <git ref>] [-H <hw>] [-U 0|1] [-E 0|1] [-o <outdir>]
#
#   -r  commit/branch/tag to build (default: HEAD). Uncommitted changes are NOT built.
#   -H  hardware: v0.2 | v0.3 | v0.4 | v1.0 (default: v1.0)
#   -U  1 = UF2 layout (app at 0x08004000, needs the UF2 bootloader), 0 = plain image at 0x08000000 (default: 1)
#   -E  1 = U4 /OE driven by the STM32 (board with U3 removed, R7 fitted): adds 2 x 48K bankswitched games (default: 0)
#   -o  output directory (default: <repo>/build/<sw>-hw<hw>[-uf2][-oe]-<sha>)
#
# From Windows, code\build-wsl.cmd runs this script in WSL with the same options.
#
# The first run installs the toolchain under $VX_TOOLS (default ~/vx):
#   - gcc-arm-none-eabi 10-2020-q4, the toolchain code/stm32/Dockerfile pins. Newer arm-none-eabi
#     versions link without errors but place the embedded menu (second .text block in the linker
#     script) in RAM instead of flash, giving a ~400 MB .bin and firmware without a menu.
#   - asm6809 2.16 (built from source; Ubuntu has no package)
#   - libopencm3 at the commit the Dockerfile pins
#   - uf2conv.py and uf2families.json from microsoft/uf2
#
# The source is cloned into $VX_TOOLS/build-src for every build, so the build sees LF line
# endings even when the Windows checkout has CRLF (core.autocrlf=true).

set -euo pipefail

REF=HEAD
HW=v1.0
UF2=1
OE=0
OUT=
while getopts "r:H:U:E:o:h" opt; do
    case $opt in
        r) REF=$OPTARG ;;
        H) HW=$OPTARG ;;
        U) UF2=$OPTARG ;;
        E) OE=$OPTARG ;;
        o) OUT=$OPTARG ;;
        *) sed -n '3,15p' "$0"; exit 1 ;;
    esac
done

case $HW in v0.2|v0.3|v0.4|v1.0) ;; *) echo "Unknown hardware '$HW' (v0.2|v0.3|v0.4|v1.0)"; exit 1 ;; esac
case $UF2 in 0|1) ;; *) echo "-U must be 0 or 1"; exit 1 ;; esac
case $OE in 0|1) ;; *) echo "-E must be 0 or 1"; exit 1 ;; esac

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
TOOLS=${VX_TOOLS:-$HOME/vx}

GCC_URL=https://developer.arm.com/-/media/Files/downloads/gnu-rm/10-2020q4/gcc-arm-none-eabi-10-2020-q4-major-x86_64-linux.tar.bz2
ASM6809_VER=2.16
ASM6809_URL=https://www.6809.org.uk/asm6809/dl/asm6809-$ASM6809_VER.tar.gz
OPENCM3_COMMIT=90753950bbe10e87b8caabfb0bd6e1d195bb24b8
UF2_COMMIT=90e9741f217f5a40c98ba74d663e408041037578

say() { printf '\n=== %s\n' "$*"; }

# --- Host packages ------------------------------------------------------------------------------
missing=()
for cmd in git make gcc curl tar bzip2 python3 hexdump; do
    command -v "$cmd" > /dev/null || missing+=("$cmd")
done
command -v python > /dev/null || missing+=(python)   # libopencm3's build calls "python"
if [ ${#missing[@]} -gt 0 ]; then
    say "Installing host packages (missing: ${missing[*]})"
    sudo apt-get update -qq
    sudo apt-get install -y -qq git make gcc curl tar bzip2 python3 python-is-python3 bsdmainutils
fi

mkdir -p "$TOOLS"

# --- arm-none-eabi 10-2020-q4 -------------------------------------------------------------------
if [ ! -x "$TOOLS/gcc10/bin/arm-none-eabi-gcc" ]; then
    say "Downloading gcc-arm-none-eabi 10-2020-q4"
    mkdir -p "$TOOLS/gcc10"
    curl -fsSL "$GCC_URL" | tar xj --strip-components=1 -C "$TOOLS/gcc10"
fi

# --- asm6809 ------------------------------------------------------------------------------------
if [ ! -x "$TOOLS/local/bin/asm6809" ]; then
    say "Building asm6809 $ASM6809_VER"
    rm -rf "$TOOLS/asm6809-$ASM6809_VER"
    curl -fsSL "$ASM6809_URL" | tar xz -C "$TOOLS"
    (cd "$TOOLS/asm6809-$ASM6809_VER" && ./configure -q --prefix="$TOOLS/local" > /dev/null \
        && make -s > /dev/null 2>&1 && make -s install > /dev/null)
fi

export PATH="$TOOLS/gcc10/bin:$TOOLS/local/bin:$PATH"

# --- libopencm3 ---------------------------------------------------------------------------------
if [ ! -f "$TOOLS/libopencm3/lib/libopencm3_stm32f4.a" ]; then
    say "Building libopencm3 ($OPENCM3_COMMIT)"
    [ -d "$TOOLS/libopencm3" ] || git clone -q https://github.com/libopencm3/libopencm3.git "$TOOLS/libopencm3"
    git -C "$TOOLS/libopencm3" checkout -q "$OPENCM3_COMMIT"
    TARGETS=stm32/f4 make -s -C "$TOOLS/libopencm3" > "$TOOLS/libopencm3-build.log" 2>&1 \
        || { tail -20 "$TOOLS/libopencm3-build.log"; exit 1; }
fi

# --- uf2conv ------------------------------------------------------------------------------------
if [ ! -f "$TOOLS/uf2/uf2conv.py" ]; then
    say "Downloading uf2conv.py ($UF2_COMMIT)"
    mkdir -p "$TOOLS/uf2"
    for f in uf2conv.py uf2families.json; do
        curl -fsSL -o "$TOOLS/uf2/$f" "https://raw.githubusercontent.com/microsoft/uf2/$UF2_COMMIT/utils/$f"
    done
fi

# --- Source -------------------------------------------------------------------------------------
SHA=$(git -C "$REPO" rev-parse --short "$REF^{commit}")
# Ask Windows git about a Windows checkout: Linux git sees every CRLF file as modified.
if command -v git.exe > /dev/null && [[ $REPO == /mnt/* ]]; then
    DIRTY=$(git.exe -C "$(wslpath -w "$REPO")" status --porcelain --untracked-files=no 2> /dev/null || true)
else
    DIRTY=$(git -C "$REPO" status --porcelain --untracked-files=no 2> /dev/null || true)
fi
if [ "$REF" = HEAD ] && [ -n "$DIRTY" ]; then
    echo "NOTE: the working tree has uncommitted changes; building the last commit ($SHA) without them."
fi
SRC=$TOOLS/build-src
rm -rf "$SRC"
git clone -q "$REPO" "$SRC"
git -C "$SRC" checkout -q "$SHA"

SW=$(sed -n 's/.*sys_opt\.sw_ver *= *0x[0-9A-Fa-f]*; *\/\/ *\(v[0-9.]*\).*/\1/p' "$SRC/code/stm32/main.c" | head -1)
[ -n "$OUT" ] || OUT=$REPO/build/${SW:-sw}-hw${HW#v}$([ "$UF2" = 1 ] && echo -uf2)$([ "$OE" = 1 ] && echo -oe)-$SHA
say "Building $SHA (SW ${SW:-?}), USE_HW=$HW USE_UF2=$UF2 USE_OE_CTRL=$OE"

# --- Menu (6809) --------------------------------------------------------------------------------
make -s -C "$SRC/code/menu" menu.bin

# --- STM32 firmware -----------------------------------------------------------------------------
cd "$SRC/code/stm32"
cp ../menu/menu.bin .
make -s menu.ld
make images USE_HW="$HW" USE_UF2="$UF2" USE_OE_CTRL="$OE" TOOLCHAIN_DIR="$TOOLS/libopencm3" > build.log 2>&1 \
    || { tail -30 build.log; exit 1; }
grep -A1 ' text' build.log

BIN=$(ls *.bin | grep -v '^menu\.bin$')
NAME=${BIN%.bin}

# Sanity checks: flash-sized image, menu embedded in flash.
SIZE=$(stat -c %s "$BIN")
if [ "$SIZE" -gt $((256 * 1024)) ]; then
    echo "ERROR: $BIN is $SIZE bytes, larger than the STM32's flash. Wrong toolchain? (see top of this script)"
    exit 1
fi
python3 - "$BIN" menu.bin << 'EOF'
import sys
fw, menu = (open(p, "rb").read() for p in sys.argv[1:3])
if fw.find(menu) < 0:
    sys.exit("ERROR: menu.bin is not embedded in the firmware image")
EOF

if [ "$UF2" = 1 ]; then
    python3 "$TOOLS/uf2/uf2conv.py" -b 0x08004000 -c "$BIN" -o "$NAME.uf2" > /dev/null
fi

# --- Output -------------------------------------------------------------------------------------
mkdir -p "$OUT"
cp "$BIN" "$NAME.elf" "$NAME.map" menu.bin "$OUT/"
[ "$UF2" = 1 ] && cp "$NAME.uf2" "$OUT/"
say "Done: $OUT"
ls -l "$OUT"
