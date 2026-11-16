#!/bin/bash
# Installs Google's Endpoint Verification native helper for the Firefox port,
# user-level only (no admin required).
#
# 1. Copies the ApiHelper binary to ~/Library/Application Support/Google/Endpoint Verification/
#    (from the system install if present, otherwise downloads + extracts the official DMG)
# 2. Verifies the downloaded distribution package is signed by Google LLC
#    (pinned Apple Team ID) and notarized by Apple before extracting
# 3. Writes a Firefox native-messaging manifest allowing this extension's ID
#
# NOTE: the binary comes from Google's own distribution server over HTTPS.
# The signature check pins Google LLC's Apple Developer Team ID (EQHXZ8M8AV),
# so a package signed by any other party is rejected even if it is validly
# signed. Run `pkgutil --check-signature` on the package yourself if you want
# to inspect the full certificate chain.
set -euo pipefail

EXT_ID="endpoint-verification@experiment.local"
GOOGLE_TEAM_ID="EQHXZ8M8AV"
BIN_DIR="$HOME/Library/Application Support/Google/Endpoint Verification"
BIN="$BIN_DIR/ApiHelper"
FF_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
FF_HOST="$FF_DIR/com.google.endpoint_verification.api_helper.json"
SRC_SYS="/Library/Application Support/Google/Endpoint Verification/ApiHelper"

if [ ! -x "$BIN" ] && [ -x "$SRC_SYS" ]; then
  mkdir -p "$BIN_DIR"
  cp "$SRC_SYS" "$BIN"
fi

if [ ! -x "$BIN" ]; then
  echo "Downloading helper DMG..."
  BASE="$(mktemp -d)"
  DMG="$BASE/ev.dmg"
  MNT=""
  cleanup() {
    if [ -n "$MNT" ]; then
      hdiutil detach "$MNT" >/dev/null 2>&1 || true
    fi
    rm -rf "$BASE"
  }
  trap cleanup EXIT
  curl -fSL -o "$DMG" "https://dl.google.com/dl/secureconnect/install/mac/EndpointVerification.dmg"

  # The mounted volume name contains spaces ("Install Endpoint Verification
  # Native Helper"), so parse hdiutil's plist output rather than splitting
  # the tab-separated text output on whitespace.
  MNT="$(hdiutil attach -nobrowse -readonly -plist "$DMG" | python3 -c '
import plistlib, sys
ents = plistlib.loads(sys.stdin.buffer.read())["system-entities"]
print(next(e["mount-point"] for e in ents if e.get("mount-point")))')"
  PKG="$MNT/EndpointVerification.pkg"

  # The distribution package (not the inner component package, which is
  # unsigned) carries the Developer ID Installer signature. pkgutil exits
  # non-zero on any signature problem; the greps pin the identity.
  SIG="$(pkgutil --check-signature "$PKG")"
  echo "$SIG"
  if ! grep -q "Developer ID Installer: Google LLC ($GOOGLE_TEAM_ID)" <<<"$SIG"; then
    echo "ERROR: package is not signed by Google LLC (Team ID $GOOGLE_TEAM_ID)." >&2
    exit 1
  fi
  if ! grep -q "Notarization: trusted by the Apple notary service" <<<"$SIG"; then
    echo "ERROR: package is not notarized by Apple." >&2
    exit 1
  fi

  # pkgutil --expand requires a target directory that does not yet exist.
  EXP="$BASE/pkg"
  pkgutil --expand "$PKG" "$EXP"
  PL_DIR="$BASE/payload"
  mkdir -p "$PL_DIR"
  (cd "$PL_DIR" && gunzip -c "$EXP/Endpoint_Verification_Native_Helper.pkg/Payload" | cpio -id 2>/dev/null)
  mkdir -p "$BIN_DIR"
  cp "$PL_DIR/Library/Application Support/Google/Endpoint Verification/ApiHelper" "$BIN"
  chmod +x "$BIN"
  echo "Helper installed: $BIN"
fi

mkdir -p "$FF_DIR"
python3 - "$FF_HOST" "$EXT_ID" "$BIN" <<'EOF'
import json, sys
dst, ext_id, bin_path = sys.argv[1], sys.argv[2], sys.argv[3]
manifest = {
    "name": "com.google.endpoint_verification.api_helper",
    "description": "Google Endpoint Verification API Helper",
    "path": bin_path,
    "type": "stdio",
    # Only this port's own extension ID is authorized to launch the helper.
    "allowed_extensions": [ext_id],
}
with open(dst, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
print("Wrote", dst)
print("Helper:", bin_path)
EOF
