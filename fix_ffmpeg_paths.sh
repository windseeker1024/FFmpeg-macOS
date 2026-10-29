#!/bin/bash
# Fix FFmpeg install names after copying the build output to its final home
# (e.g. $HOME/ffmpeg). Converts library ids and inter-library references to
# @rpath, and points bin/ executables at @executable_path/../lib.
# Run this script from the FFmpeg installation directory.

set -e

FFMPEG_DIR="$(pwd)"

if [ ! -d "$FFMPEG_DIR/lib" ]; then
    echo "Error: $FFMPEG_DIR/lib not found"
    echo "Please run this script from your FFmpeg installation directory (e.g., $HOME/ffmpeg)"
    exit 1
fi

echo "Fixing FFmpeg library paths in $FFMPEG_DIR/lib"
echo ""

cd "$FFMPEG_DIR/lib" || exit 1

# Detect the stale build-tree prefix from any library's load commands.
# Matches any ".../install_(arm64|x86_64|universal)" path, so the build
# directory can live anywhere (no special naming requirement).
OLD_PREFIX=$(otool -L libavcodec.dylib 2>/dev/null | grep -oE '/[^[:space:]]*/install_(arm64|x86_64|universal)' | head -1)

if [ -z "$OLD_PREFIX" ]; then
    OLD_PREFIX=$(for f in *.dylib; do otool -L "$f" 2>/dev/null | grep -oE '/[^[:space:]]*/install_(arm64|x86_64|universal)' && break; done | head -1)
fi

if [ -z "$OLD_PREFIX" ]; then
    echo "✅ Libraries already use @rpath, no changes needed."
    exit 0
fi

echo "Detected old prefix: $OLD_PREFIX"
echo "Will replace with: @rpath"
echo ""

# Fix every real library file (symlink aliases resolve to the same file and
# are skipped). The install id is set to the major-version soname
# (libavcodec.62.28.103.dylib -> libavcodec.62.dylib) so it matches the
# name dependents record at link time.
for lib in *.dylib; do
    if [ ! -f "$lib" ] || [ -L "$lib" ]; then
        continue
    fi
    idname="$lib"
    if [[ "$lib" =~ ^(.*\.[0-9]+)\.[0-9]+\.[0-9]+\.dylib$ ]]; then
        idname="${BASH_REMATCH[1]}.dylib"
    fi
    echo "Processing $lib (id @rpath/$idname)..."

    install_name_tool -id "@rpath/$idname" "$lib"

    otool -L "$lib" | grep "$OLD_PREFIX" | awk '{print $1}' | while read dep; do
        libname=$(basename "$dep")
        echo "  Changing $dep -> @rpath/$libname"
        install_name_tool -change "$dep" "@rpath/$libname" "$lib"
    done
done

# Fix executables in bin/: rewrite their build-tree deps to
# @executable_path/../lib and add an rpath entry so the libraries' own
# @rpath references resolve when loaded by the executable.
if [ -d "$FFMPEG_DIR/bin" ]; then
    echo ""
    echo "Fixing executables in $FFMPEG_DIR/bin"
    cd "$FFMPEG_DIR/bin" || exit 1

    for tool in *; do
        # Skip anything that is not a Mach-O image (scripts, stubs, leftovers).
        if [ ! -f "$tool" ] || ! file "$tool" | grep -q 'Mach-O'; then
            continue
        fi
        echo "Processing $tool..."

        otool -L "$tool" | grep "$OLD_PREFIX" | awk '{print $1}' | while read dep; do
            libname=$(basename "$dep")
            echo "  Changing $dep -> @executable_path/../lib/$libname"
            install_name_tool -change "$dep" "@executable_path/../lib/$libname" "$tool"
        done
        install_name_tool -add_rpath "@executable_path/../lib" "$tool" 2>/dev/null || true
    done
fi

echo ""
echo "Done! Verifying..."
echo ""
echo "Checking libavcodec.dylib:"
otool -L libavcodec.dylib 2>/dev/null | head -5 || (cd "$FFMPEG_DIR/lib" && otool -L libavcodec.dylib | head -5)

echo ""
echo "✅ FFmpeg paths fixed!"
echo "Libraries use @rpath; executables load them via @executable_path/../lib."
