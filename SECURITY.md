# Security Policy

## Supported state

**Unsupported.** This is an experimental port provided as-is. There is no
maintainer commitment to security fixes, SLAs, or updates. Treat it as a
proof of concept until you have audited it yourself.

## Reporting a vulnerability

Open a **private security advisory** on this GitHub repository (Security →
"Report a vulnerability"), or contact a maintainer directly. Please do not
open public issues for suspected vulnerabilities.

Note that most findings in the compiled bundle (98%+ of the code) can only
be fixed upstream by Google in the official Endpoint Verification
extension. Report those to Google via
[Chrome's security bug tracker](https://bugs.chromium.org/p/chromium/issues/entry?template=Security%20Bug);
this project tracks the port-specific files only (`compat_shim.js`,
`setup-native-host.sh`, `manifest.json`, CI).

## Threat model & permission justification

| Permission | Why it is needed | Risk if abused |
|---|---|---|
| `cookies` | Read SAPISID/APISID cookies to sign `SAPISIDHASH` auth headers against Google's APIs | Credential theft (cookies grant account access) |
| `nativeMessaging` | Talk to Google's `ApiHelper` binary for device identifiers and disk-encryption state | Local binary execution is constrained by the native-host manifest, which authorizes only this extension's ID |
| `idle` | Sync on idle/screen-unlock events | Low |
| `storage`, `alarms` | Persist sync state, schedule retries | Low |
| `*://*.google.com/*` | Reach `accounts.google.com` and `secureconnect-pa.clients6.google.com` with credentials | Requests are issued by Google's compiled code; the port adds no network code of its own |

What the port deliberately does **not** do:

- No `webRequest`, `<all_urls>`, content scripts, or tabs access to
  browsing activity.
- No traffic interception, header rewriting, or telemetry added by the
  port (the debug log-server tee that existed during development was
  removed before publication).
- No remote code: CSP is `script-src 'self'; object-src 'self'`.

## Known limitations

- **Opaque core.** `background_service_worker.js` (~19,700 lines) is
  Google's compiled output. The port verifies it byte-identical against
  the official CRX (see `verify.sh`) but cannot audit it.
- **MV2 event page.** Uses deprecated Manifest V2; Firefox's MV2 sunset
  applies.
- **Attestation is absent, not spoofed.** Chrome-only device-trust APIs
  are stubbed; Google's backend receives a Firefox profile with weaker
  device evidence.
- **Native helper trust.** `setup-native-host.sh` downloads Google's
  proprietary `ApiHelper` from `dl.google.com` (signature-checked) and
  runs it user-level. Its behavior is outside this repo's control.

## Pre-publication checks

Run before every release (also enforced in CI, see
`.github/workflows/ci.yml`):

```sh
./verify.sh          # provenance: compiled files byte-identical to official CRX
shellcheck setup-native-host.sh verify.sh
node --check compat_shim.js
web-ext lint .        # Firefox packaging/permissions validation (npm i -g web-ext)
gitleaks detect .     # secret scan (the Google API key in the bundle is a public CWS key, intentional)
```
