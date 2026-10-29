#!/bin/bash
# One-shot FFmpeg deployment: copy a freshly built tree to a prefix
# (default $HOME/ffmpeg), fix install names (@rpath) and executables
# (@executable_path), repair pkgconfig prefixes, then verify the result.
# The existing prefix, if any, is backed up first (prefix.bak-<timestamp>).
#
# Usage:
#   bash install_to_prefix.sh [source_dir] [prefix_dir]
#     source_dir  default: <repo>/ffmpeg-build/install_universal
#     prefix_dir  default: $HOME/ffmpeg
#
# Typical CI packaging machine usage:
#   bash install_to_prefix.sh                       # deploy to ~/ffmpeg
#   bash install_to_prefix.sh ~/Downloads/universal /Users/beem/ffmpeg
#
# NOTE for CI packaging machines: the pre-placed dylib directory referenced
# by SHARED_LIB_DIR_MAC (shared-library-mac) is a SEPARATE copy — update it
# too, or shipped packages keep bundling the old dylibs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$SCRIPT_DIR/ffmpeg-build/install_universal}"
PREFIX="${2:-$HOME/ffmpeg}"

if [ ! -d "$SRC/lib" ]; then
    echo "Error: source FFmpeg tree not found at $SRC (expected lib/ inside)"
    exit 1
fi

echo "Source: $SRC"
echo "Prefix: $PREFIX"
echo ""

# 1. Back up an existing deployment (timestamped, never overwritten).
if [ -e "$PREFIX" ]; then
    BACKUP="${PREFIX}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing $PREFIX -> $BACKUP"
    mv "$PREFIX" "$BACKUP"
fi

# 2. Copy the fresh tree.
cp -R "$SRC" "$PREFIX"

# 3. Fix install names / executable references (idempotent).
(cd "$PREFIX" && bash "$SCRIPT_DIR/fix_ffmpeg_paths.sh")

# 4. Point pkgconfig files at this machine's prefix.
python3 "$SCRIPT_DIR/fix_ffmpeg_pkgconfig.py" "$PREFIX"

# 5. Verify: universal slices, @rpath ids, pkgconfig resolution, tools run.
echo ""
echo "Verifying deployment..."
FAIL=0
for lib in "$PREFIX"/lib/*.dylib; do
    [ -f "$lib" ] || continue
    [ -L "$lib" ] && continue
    name=$(basename "$lib")
    archs=$(lipo -archs "$lib")
    if ! echo "$archs" | grep -q arm64 || ! echo "$archs" | grep -q x86_64; then
        echo "  FAIL $name: not universal ($archs)"
        FAIL=1
        continue
    fi
    id=$(otool -D "$lib" | tail -1)
    case "$id" in
        @rpath/*) ;;
        *) echo "  FAIL $name: install id is not @rpath ($id)"; FAIL=1;;
    esac
    minos=$(otool -l "$lib" | awk '/LC_BUILD_VERSION/{x=1} x&&/minos/{print $2; x=0}' | sort -u | tr '\n' ' ')
    echo "  OK   $name [$archs] minos=[$minos]"
done

PC_VERSION=$(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --modversion libavcodec 2>/dev/null || true)
if [ -z "$PC_VERSION" ]; then
    echo "  FAIL pkgconfig: libavcodec not resolvable from $PREFIX/lib/pkgconfig"
    FAIL=1
else
    echo "  OK   pkgconfig libavcodec=$PC_VERSION"
fi

if [ -x "$PREFIX/bin/ffprobe" ]; then
    echo "  OK   $(HOME= "$PREFIX/bin/ffprobe" -version 2>&1 | head -1)"
else
    echo "  FAIL bin/ffprobe missing or not executable"
    FAIL=1
fi

echo ""
if [ "$FAIL" -ne 0 ]; then
    echo "✗ Deployment FAILED verification — inspect the output above."
    exit 1
fi
echo "✅ Deployed to $PREFIX"
[ -e "${BACKUP:-}" ] && echo "   Previous version kept at $BACKUP"
echo "   Reminder (CI machines): also update the SHARED_LIB_DIR_MAC pre-placed"
echo "   dylib directory if this machine bundles ffmpeg into packages."
