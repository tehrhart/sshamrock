#!/usr/bin/env bash
set -euo pipefail

# Build script: assembles the SSH web client from libapps sources.
# Usage: ./build/assemble.sh [path-to-libapps]
#
# Requires: npm (for rollup deps), libapps checkout

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIBAPPS="${1:-$HOME/Desktop/libapps}"
DIST="$PROJECT_DIR/dist"

if [ ! -d "$LIBAPPS/nassh" ]; then
  echo "Error: libapps not found at $LIBAPPS"
  echo "Usage: $0 [path-to-libapps]"
  exit 1
fi

echo "==> Cleaning dist/"
rm -rf "$DIST"
mkdir -p "$DIST"

# ---- Step 1: Build rollup deps (generates deps_*.rollup.js) ----
echo "==> Building rollup dependencies..."
if [ ! -d "$LIBAPPS/node_modules" ]; then
  (cd "$LIBAPPS" && npm install)
fi

# Ensure node_modules symlinks exist for sub-projects.
for sub in nassh hterm libdot wasi-js-bindings; do
  if [ ! -d "$LIBAPPS/$sub/node_modules" ]; then
    ln -sfn "$LIBAPPS/node_modules" "$LIBAPPS/$sub/node_modules"
  fi
done

# Build in dependency order: libdot → hterm → nassh.
echo "    Rolling up libdot..."
(cd "$LIBAPPS/libdot" && LIBAPPS_DEPS_ONLY=1 npx rollup -c 2>&1 | tail -1)

echo "    Rolling up hterm..."
(cd "$LIBAPPS/hterm" && npx rollup -c 2>&1 | tail -1)

echo "    Rolling up nassh..."
(cd "$LIBAPPS/nassh" && npx rollup -c 2>&1 | tail -1)

# ---- Step 2: Copy library sources ----
echo "==> Copying libdot..."
mkdir -p "$DIST/libdot/js" "$DIST/libdot/dist/js"
cp "$LIBAPPS/libdot/index.js" "$DIST/libdot/"
cp "$LIBAPPS/libdot/js/"*.js "$DIST/libdot/js/"
cp "$LIBAPPS/libdot/dist/js/"*.js "$DIST/libdot/dist/js/"

echo "==> Copying hterm..."
mkdir -p "$DIST/hterm/js" "$DIST/hterm/dist/js"
cp "$LIBAPPS/hterm/index.js" "$DIST/hterm/"
cp "$LIBAPPS/hterm/js/"*.js "$DIST/hterm/js/"
# Copy hterm dist (generated resources).
if [ -d "$LIBAPPS/hterm/dist/js" ]; then
  cp "$LIBAPPS/hterm/dist/js/"*.js "$DIST/hterm/dist/js/"
fi
# Copy hterm third_party (wcwidth, intl-segmenter).
cp -r "$LIBAPPS/hterm/third_party" "$DIST/hterm/"

echo "==> Copying wasi-js-bindings..."
mkdir -p "$DIST/wasi-js-bindings/js/wasi"
cp "$LIBAPPS/wasi-js-bindings/index.js" "$DIST/wasi-js-bindings/"
cp "$LIBAPPS/wasi-js-bindings/js/"*.js "$DIST/wasi-js-bindings/js/"
# Copy WASI subdirectory if present.
if [ -d "$LIBAPPS/wasi-js-bindings/js/wasi" ]; then
  cp "$LIBAPPS/wasi-js-bindings/js/wasi/"*.js "$DIST/wasi-js-bindings/js/wasi/" 2>/dev/null || true
fi

echo "==> Copying wassh..."
mkdir -p "$DIST/wassh/js"
cp "$LIBAPPS/wassh/js/"*.js "$DIST/wassh/js/"

# ---- Step 3: Copy nassh sources ----
echo "==> Copying nassh..."
mkdir -p "$DIST/nassh/js" "$DIST/nassh/css"

# Copy all JS (source + generated rollup deps).
cp "$LIBAPPS/nassh/js/"*.js "$DIST/nassh/js/"

# Copy CSS.
cp "$LIBAPPS/nassh/css/"*.css "$DIST/nassh/css/"

# Copy locales (for i18n message loading).
cp -r "$LIBAPPS/nassh/_locales" "$DIST/nassh/"

# Copy images.
cp -r "$LIBAPPS/nassh/images" "$DIST/nassh/"

# Copy nassh third_party (google-smart-card, fonts, etc).
cp -r "$LIBAPPS/nassh/third_party" "$DIST/nassh/"

# Create symlinks inside nassh/ matching what mkdeps creates.
# nassh JS files import from ../wassh/, ../libdot/ etc.
ln -sfn ../wassh "$DIST/nassh/wassh"
ln -sfn ../libdot "$DIST/nassh/libdot"
ln -sfn ../hterm "$DIST/nassh/hterm"
ln -sfn ../wasi-js-bindings "$DIST/nassh/wasi-js-bindings"

# ---- Step 4: WASM binary ----
echo "==> Setting up WASM binary..."
mkdir -p "$DIST/plugin/wasm"

# Check for pre-built binary in ssh_client output.
if [ -f "$LIBAPPS/ssh_client/output/plugin/wasm/ssh.wasm" ]; then
  cp "$LIBAPPS/ssh_client/output/plugin/wasm/ssh.wasm" "$DIST/plugin/wasm/"
  echo "    Found pre-built ssh.wasm"
else
  echo "    WARNING: ssh.wasm not found at $LIBAPPS/ssh_client/output/plugin/wasm/"
  echo "    You need to either:"
  echo "      1. Build it: cd $LIBAPPS/ssh_client && ./build.sh"
  echo "      2. Extract it from the Chrome extension .crx file"
  echo "    Place the file at: $DIST/plugin/wasm/ssh.wasm"
fi

# ---- Step 5: Locale files at root (lib.f.getURL uses origin + path) ----
ln -sfn nassh/_locales "$DIST/_locales"

# ---- Step 6: Copy custom web app files ----
echo "==> Copying web app sources..."
cp "$PROJECT_DIR/src/index.html" "$DIST/"
mkdir -p "$DIST/js" "$DIST/css"
cp "$PROJECT_DIR/src/js/"*.js "$DIST/js/"
cp "$PROJECT_DIR/src/css/"*.css "$DIST/css/"

# ---- Step 7: Remove test files to reduce size ----
echo "==> Cleaning up test files..."
find "$DIST" -name '*_tests.js' -delete
find "$DIST" -name '*_test.js' -delete
find "$DIST" -name 'chrome_mock_for_test.js' -delete
find "$DIST" -name 'crosh_main.js' -delete

echo ""
echo "==> Build complete: $DIST"
echo ""
echo "To serve locally with required headers:"
echo "  python3 -m http.server 8080 --directory $DIST"
echo ""
echo "Note: You must configure COOP/COEP headers for SharedArrayBuffer."
echo "For development, use the serve.py script or a reverse proxy."
