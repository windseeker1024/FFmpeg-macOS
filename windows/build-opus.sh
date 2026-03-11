#!/bin/bash
set -e

# -- locate script directory (follows symlinks) --
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# -- default paths (relative to script directory) --
SRC_DIR="${SCRIPT_DIR}/opus"
BUILD_DIR="${SCRIPT_DIR}/build-opus"
PREFIX=""   # set after BUILD_DIR is finalised (see below)

# -- parse command-line arguments --
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-dir)
            SRC_DIR="$2"; shift 2 ;;
        --build-dir)
            BUILD_DIR="$2"; shift 2 ;;
        --prefix)
            PREFIX="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--src-dir DIR] [--build-dir DIR] [--prefix DIR]"
            echo "  --src-dir   opus source directory    (default: \${SCRIPT_DIR}/opus)"
            echo "  --build-dir Build output directory   (default: \${SCRIPT_DIR}/build-opus)"
            echo "  --prefix    Install prefix           (default: \${BUILD_DIR}/install)"
            exit 0 ;;
        *)
            echo "[WARN] Unknown argument: $1"; shift ;;
    esac
done

# -- resolve PREFIX default after BUILD_DIR is known --
[[ -z "$PREFIX" ]] && PREFIX="${BUILD_DIR}/install"

# -- use MinGW-w64 toolchain (not Cygwin GCC) --
# Required packages (install once inside any MSYS2 shell):
#   pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-make
export PATH="/mingw64/bin:$PATH"

echo "===== opus build (MSYS2/MinGW-w64) ====="
echo "[INFO] Source dir  : $SRC_DIR"
echo "[INFO] Build dir   : $BUILD_DIR"
echo "[INFO] Install dir : $PREFIX"

# -- check gcc --
if ! command -v gcc &>/dev/null; then
    echo "[ERROR] gcc not found. Install the MinGW-w64 toolchain:"
    echo "  pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-make"
    exit 1
fi

echo "[INFO] Compiler    : $(gcc --version | head -1)"

# -- verify source directory --
if [[ ! -f "$SRC_DIR/configure" ]]; then
    echo "[ERROR] opus configure not found: $SRC_DIR/configure"
    echo "        Clone the source:"
    echo "          git clone https://gitlab.xiph.org/xiph/opus.git $SRC_DIR"
    exit 1
fi

# -- create and enter the out-of-tree build directory --
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo ""
echo "[INFO] Running configure ..."
"$SRC_DIR/configure" \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-doc \
    --disable-extra-programs

echo ""
echo "[INFO] Building ($(nproc) jobs) ..."
make -j"$(nproc)"

echo ""
echo "[INFO] Installing ..."
make install

echo ""
echo "[OK] opus built and installed."
echo "     Headers : ${PREFIX}/include/opus"
echo "     Lib     : ${PREFIX}/lib"
echo "     DLL     : ${PREFIX}/bin/libopus-*.dll"
