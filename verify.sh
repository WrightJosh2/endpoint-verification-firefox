#!/bin/bash
# verify.sh — reproducible provenance check for endpoint-verification-firefox.
#
# Downloads the official Endpoint Verification CRX from Google's update
# service and asserts that every compiled file in this repo is byte-identical
# to the official package. Fails loudly on any difference.
#
# Intentional differences (manifest MV2 conversion, popup.html logo removal,
# messages.json key ordering, port-only files) are excluded from the
# byte-identity check; see README.md "Verification".
set -euo pipefail

EXT_ID="callobklhcbilhphinckomhgkigmfocg"
VERSION="1.140.0"
KNOWN_CRX_SHA256="617bdda6bc41ac9e177691d489c22de458fa38bd738e792d964c61b99c151eed"

# Compiled files that must be byte-identical to the official CRX.
COMPILED_FILES=(
  background_service_worker.js
  popup_script.js
  options_script.js
  log_script.js
  offscreen_script.js
  mdl_all_js_compiled.js
  iframe_sandbox.html
  log.html
  options.html
  log.css
  options.css
  material_design_lite.css
  popup.css
  css/material_icons/material_icons.css
  css/roboto/roboto.css
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading official CRX ($VERSION, id $EXT_ID)..."
CRX="$WORK/ev.crx"
curl -fsSL -o "$CRX" \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=138.0.0.0&acceptformat=crx2,crx3&x=id%3D${EXT_ID}%26uc"

HASH="$(shasum -a 256 "$CRX" | awk '{print $1}')"
echo "CRX SHA256: $HASH"
if [ "$HASH" != "$KNOWN_CRX_SHA256" ]; then
  {
    echo "PROVENANCE CHECK FAILED: CRX hash mismatch."
    echo "  Expected: $KNOWN_CRX_SHA256"
    echo "  Got:      $HASH"
    echo "Google has likely shipped a new version of the extension; the files in"
    echo "this repo still correspond to the $VERSION snapshot. Re-derive the port"
    echo "from the new CRX, then update VERSION and KNOWN_CRX_SHA256."
    echo "This is the intended CI failure mode for a stale snapshot."
  } >&2
  exit 1
fi

python3 - "$CRX" "$WORK/official" <<'EOF'
import sys, zipfile, io
d = open(sys.argv[1], 'rb').read()
zipfile.ZipFile(io.BytesIO(d[d.index(b'PK\x03\x04'):])).extractall(sys.argv[2])
EOF

FAIL=0
echo
echo "Byte-identity check against official CRX:"
for f in "${COMPILED_FILES[@]}"; do
  if cmp -s "$WORK/official/$f" "$f"; then
    echo "  IDENTICAL  $f"
  else
    echo "  DIFFERS    $f" >&2
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "PROVENANCE CHECK FAILED" >&2
  exit 1
fi
echo "PROVENANCE CHECK PASSED — all compiled files match the official CRX."
