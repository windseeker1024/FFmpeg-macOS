#!/bin/bash
# Rewrite a deployed FFmpeg tree's dylib install names to ABSOLUTE paths
# under the tree's own lib/ directory (the convention of a plain
# `make install`, e.g. Homebrew).
#
# When to use: fix_ffmpeg_paths.sh leaves ids and inter-dependencies as
# @rpath/<soname>, which requires every consumer to carry the library
# directory in its LC_RPATH (or in DYLD_FALLBACK_LIBRARY_PATH). Consumers
# that link without any rpath — e.g. Rust test binaries built by
# ffmpeg-sys-next — then fail at load time with
#   dyld: Library not loaded: @rpath/libavutil.60.dylib
# Absolute install names are embedded verbatim into whatever links against
# the tree, so no rpath is needed anywhere. Use this on build machines whose
# previous FFmpeg install used absolute names (that is the ffmpeg default).
#
# The script handles any starting state:
#   - @rpath/<soname> refs           → repointed to <libdir>/<soname>
#   - absolute refs into the BUILD tree (e.g. .../ffmpeg-build/install_*) → repointed
#   - refs already under <libdir>    → left untouched
#
# Usage:
#   bash fix_absolute_names.sh [prefix_dir]     # default: $HOME/ffmpeg
#   Run AFTER deploying (e.g. after install_to_prefix.sh). Idempotent.

set -euo pipefail

FFMPEG_DIR="${1:-$HOME/ffmpeg}"

if [ ! -d "$FFMPEG_DIR/lib" ]; then
    echo "Error: $FFMPEG_DIR/lib not found"
    echo "Usage: bash fix_absolute_names.sh [prefix_dir]   (default: \$HOME/ffmpeg)"
    exit 1
fi

LIBDIR="$(cd "$FFMPEG_DIR/lib" && pwd)"
echo "Rewriting install names to absolute form under: $LIBDIR"
echo ""

changed=0
skipped=0

for lib in "$LIBDIR"/lib*.dylib; do
    # Real files only; the soname/unversioned symlinks resolve to the same file.
    if [ ! -f "$lib" ] || [ -L "$lib" ]; then
        continue
    fi
    full_name="$(basename "$lib")"

    # The install id uses the SONAME path (libavcodec.62.dylib), matching what
    # ffmpeg's own `make install` records.
    soname="$(echo "$full_name" | sed -E 's/^(lib[A-Za-z_]+)\.([0-9]+)\..*\.dylib$/\1.\2.dylib/')"
    want_id="$LIBDIR/$soname"

    id="$(otool -D "$lib" | tail -1)"

    # FFmpeg sibling deps (libav*/libsw*) that do not already point into $LIBDIR.
    refs="$(otool -L "$lib" \
        | awk '{print $1}' \
        | grep -E '^(@rpath/|/)(libav|libsw)' \
        | grep -v -F "$LIBDIR/" \
        || true)"

    if [ "$id" = "$want_id" ] && [ -z "$refs" ]; then
        echo "  skip $full_name (already correct)"
        skipped=$((skipped + 1))
        continue
    fi

    echo "Processing $full_name..."

    if [ "$id" != "$want_id" ]; then
        echo "  id: $id -> $want_id"
        install_name_tool -id "$want_id" "$lib"
    fi

    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        dep_name="$(basename "$dep")"
        echo "  $dep -> $LIBDIR/$dep_name"
        install_name_tool -change "$dep" "$LIBDIR/$dep_name" "$lib"
    done <<< "$refs"

    changed=$((changed + 1))
done

echo ""
echo "Verification:"
for lib in "$LIBDIR"/libavcodec.*.dylib "$LIBDIR"/libavutil.*.dylib; do
    [ -f "$lib" ] && [ ! -L "$lib" ] || continue
    echo "  $(basename "$lib") id: $(otool -D "$lib" | tail -1)"
done
stray="$(otool -L "$LIBDIR"/libavcodec.*.dylib \
    | awk '{print $1}' \
    | grep -E '^(@rpath/|/)(libav|libsw)' \
    | grep -v -F "$LIBDIR/" \
    | head -1 || true)"
if [ -n "$stray" ]; then
    echo "  ✗ ffmpeg ref still outside $LIBDIR: $stray"
    exit 1
fi
echo ""
echo "✅ Done: $changed file(s) rewritten, $skipped already correct."
echo "Link consumers (cargo test, nextest, ctest…) now embed the absolute"
echo "paths and no longer need an rpath or DYLD_FALLBACK_LIBRARY_PATH."
