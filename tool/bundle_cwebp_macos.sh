#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/macos/Build/Products/Release/EPUB 工具箱.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

CWEBP="${CWEBP_PATH:-}"
if [[ -z "$CWEBP" ]]; then
  CWEBP="$(command -v cwebp || true)"
fi
if [[ -z "$CWEBP" && -x /opt/homebrew/bin/cwebp ]]; then
  CWEBP="/opt/homebrew/bin/cwebp"
fi
if [[ -z "$CWEBP" && -x /usr/local/bin/cwebp ]]; then
  CWEBP="/usr/local/bin/cwebp"
fi
if [[ -z "$CWEBP" || ! -x "$CWEBP" ]]; then
  echo "cwebp not found. Install it before packaging: brew install webp" >&2
  exit 1
fi

RESOURCES="$APP_PATH/Contents/Resources"
BIN_DIR="$RESOURCES/bin"
LIB_DIR="$RESOURCES/lib"
mkdir -p "$BIN_DIR" "$LIB_DIR"

BREW_PREFIX="${HOMEBREW_PREFIX:-}"
if [[ -z "$BREW_PREFIX" ]]; then
  BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
fi
if [[ -z "$BREW_PREFIX" ]]; then
  if [[ -d /opt/homebrew ]]; then
    BREW_PREFIX="/opt/homebrew"
  elif [[ -d /usr/local/Homebrew || -d /usr/local/opt ]]; then
    BREW_PREFIX="/usr/local"
  fi
fi
if [[ -z "$BREW_PREFIX" ]]; then
  echo "Homebrew prefix not found. Install webp first: brew install webp" >&2
  exit 1
fi

copy_lib() {
  local src="$1"
  local dest_name="$2"
  if [[ ! -f "$src" ]]; then
    echo "Missing dependency: $src" >&2
    exit 1
  fi
  cp -f "$src" "$LIB_DIR/$dest_name"
  chmod 755 "$LIB_DIR/$dest_name"
}

cp -f "$CWEBP" "$BIN_DIR/cwebp"
chmod 755 "$BIN_DIR/cwebp"

copy_lib "$BREW_PREFIX/opt/webp/lib/libwebpdemux.2.dylib" "libwebpdemux.2.dylib"
copy_lib "$BREW_PREFIX/opt/webp/lib/libwebp.7.dylib" "libwebp.7.dylib"
copy_lib "$BREW_PREFIX/opt/webp/lib/libsharpyuv.0.dylib" "libsharpyuv.0.dylib"
copy_lib "$BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib" "libpng16.16.dylib"
copy_lib "$BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib" "libjpeg.8.dylib"
copy_lib "$BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib" "libtiff.6.dylib"
copy_lib "$BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib" "libzstd.1.dylib"
copy_lib "$BREW_PREFIX/opt/xz/lib/liblzma.5.dylib" "liblzma.5.dylib"

install_name_tool -add_rpath "@loader_path/../lib" "$BIN_DIR/cwebp" 2>/dev/null || true
install_name_tool -change "$BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib" @rpath/libpng16.16.dylib "$BIN_DIR/cwebp"
install_name_tool -change "$BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib" @rpath/libjpeg.8.dylib "$BIN_DIR/cwebp"
install_name_tool -change "$BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib" @rpath/libtiff.6.dylib "$BIN_DIR/cwebp"

for dylib in "$LIB_DIR"/*.dylib; do
  base="$(basename "$dylib")"
  install_name_tool -id "@rpath/$base" "$dylib" 2>/dev/null || true
  install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
  install_name_tool -change "$BREW_PREFIX/opt/webp/lib/libwebpdemux.2.dylib" @rpath/libwebpdemux.2.dylib "$dylib" 2>/dev/null || true
  install_name_tool -change "$BREW_PREFIX/opt/webp/lib/libwebp.7.dylib" @rpath/libwebp.7.dylib "$dylib" 2>/dev/null || true
  install_name_tool -change "$BREW_PREFIX/opt/webp/lib/libsharpyuv.0.dylib" @rpath/libsharpyuv.0.dylib "$dylib" 2>/dev/null || true
  install_name_tool -change "$BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib" @rpath/libjpeg.8.dylib "$dylib" 2>/dev/null || true
  install_name_tool -change "$BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib" @rpath/libzstd.1.dylib "$dylib" 2>/dev/null || true
  install_name_tool -change "$BREW_PREFIX/opt/xz/lib/liblzma.5.dylib" @rpath/liblzma.5.dylib "$dylib" 2>/dev/null || true
done

codesign --force --sign - "$LIB_DIR"/*.dylib "$BIN_DIR/cwebp" >/dev/null 2>&1 || true

"$BIN_DIR/cwebp" -version >/dev/null
echo "Bundled cwebp into $APP_PATH"
