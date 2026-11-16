# Endpoint Verification — Unofficial Firefox Port

> **This project is not affiliated with, endorsed by, or supported by
> Google LLC or Mozilla.** It is an experiment provided **as-is, with no
> guarantees of any kind**. Running a modified build against Google's
> services, and redistributing Google's compiled code, may violate
> Google's Terms of Service — you assume that risk. See
> [LICENSE](LICENSE), [NOTICE](NOTICE), and the
> [Caveats](#caveats--no-guarantees) section before using it.

An unofficial port of Google's **Endpoint Verification** browser extension
(internal name: *SecureConnect*) to Firefox.

Endpoint Verification is a Google Workspace component that reports the
identity and security posture of a desktop/laptop to the Workspace Admin
console — used by organizations to get visibility into unmanaged (BYOD)
devices that sign in to corporate Google accounts. Google ships it for
Chrome (and it is preinstalled on ChromeOS-managed devices), but has never
released it for Firefox, even though the extension's own code contains
complete, functional Firefox support.

This repo takes Google's compiled Chrome extension and runs it on Firefox.

---

## How it works

### The Firefox support already exists — Google just doesn't ship it

The extension's compiled background script contains first-class Firefox
code paths: a `browser === 3` (Firefox) branch in its runtime detection,
dedicated Firefox metrics counters
(`/client_streamz/secureconnect/operation_firefox_internal` /
`..._firefox_external`), and an `X-Origin` header flow that lets a
`moz-extension://`-origin extension authenticate against Google's
services the same way an `https://` web origin would. The port simply
unlocks this path.

### Architecture

```
┌────────────────────────────── Firefox ──────────────────────────────┐
│  manifest.json (MV2 event page, not MV3 service worker)             │
│                                                                     │
│  compat_shim.js              ← port-specific (readable source)      │
│    • Stubs Chrome-only APIs so Google's code runs unmodified:       │
│      enterprise.deviceAttributes / enterprise.reportingPrivate /    │
│      enterprise.platformKeys / platformKeys / gcm / offscreen /     │
│      identity / management.getSelf / idle extras                    │
│    • No network traffic is intercepted, logged or rewritten        │
│                                                                     │
│  background_service_worker.js ← Google's compiled code (~19.7k      │
│    lines, from Chrome extension v1.140.0):                          │
│    • Detects signed-in Workspace accounts                           │
│    • Collects device info (OS, hostname, serial, MAC, encryption)  │
│    • Signs requests with SAPISIDHASH (real moz-extension origin,   │
│      declared via X-Origin — Google's own Firefox path)            │
│    • Syncs device state to Google's SecureConnect backend          │
│                                                                     │
│  popup / options / log pages  ← Google's compiled UI code            │
└───────────────┬─────────────────────────────────────────────────────┘
                │ native messaging (stdio, JSON)
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ ApiHelper (Google's native helper binary — NOT in this repo)         │
│ Installed user-level by setup-native-host.sh from Google's official │
│ DMG; reads device identifiers and disk-encryption state from macOS.  │
└───────────────┬─────────────────────────────────────────────────────┘
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Google backend                                                       │
│  accounts.google.com/ListAccounts        (account discovery)         │
│  secureconnect-pa.clients6.google.com    (getManagementState,        │
│                                           reportDeviceState,         │
│                                           enrollDevice)              │
│  /client_streamz/secureconnect/*          (telemetry counters)        │
└─────────────────────────────────────────────────────────────────────┘
```

The native-messaging host manifest written by `setup-native-host.sh`
authorizes **only this extension's ID** to launch the helper. The ID is
an allow-list entry, not a secret: it only names who may talk to the
helper, and only an extension you install into your own Firefox profile
can hold it. The stronger gate is on the helper side — the installer
rejects any distribution package that is not signed by
**Google LLC (Apple Developer Team ID `EQHXZ8M8AV`)** and notarized by
Apple, and `verify.sh` proves the extension code is byte-identical to
Google's official CRX.

## Setup

1. **Install the native helper** (macOS, user-level, no admin needed):

   ```sh
   ./setup-native-host.sh
   ```

   This copies (or downloads, signature-checks, and extracts) Google's
   official `ApiHelper` binary — the download path verifies the
   distribution package is signed by Google LLC (Team ID `EQHXZ8M8AV`,
   pinned) and notarized by Apple — and writes the Firefox
   native-messaging manifest at
   `~/Library/Application Support/Mozilla/NativeMessagingHosts/`.

2. **Load the extension** in Firefox:
   - Temporarily: `about:debugging#/runtime/this-firefox` → *Load
     Temporary Add-on* → select `manifest.json`. Note that a temporary
     add-on gets a new ID on every restart, which the native-messaging
     manifest won't authorize — for daily use, install permanently.
   - Permanently: sign with `web-ext` (`web-ext sign`) or install via
     `about:config` → `xpinstall.signatures.required` = false for a
     development install in a dedicated profile.

3. Sign in to a Google Workspace account in the browser, open the
   extension's popup, and press **Sync Now**.

## Privacy & security — what actually happens

Read this before deciding to run it.

- **This is device-management software.** It reports your device's OS,
  hostname, hardware identifiers (serial number, MAC addresses), disk
  encryption state, and the identity of signed-in Google accounts to
  Google's SecureConnect backend, where a Workspace administrator of the
  signed-in domain can see it. That is its entire purpose.
- **The core code is a minified binary blob.** You cannot meaningfully
  audit 19.7k lines of compiled output. You are trusting that it is an
  unmodified copy of Google's extension (see [Verification](#verification)
  for how to check that yourself).
- **Attestation is weaker than on Chrome.** Chrome-only APIs
  (`enterprise.*`, `platformKeys` device certificate challenges) are
  stubbed out. Data is therefore *absent*, never fabricated — Google's
  backend receives a Firefox-shaped profile, not a spoofed Chrome one.
- **Auth flows are untouched.** The port does not intercept, log, or
  rewrite any network traffic or auth headers. An earlier experiment that
  re-signed the SAPISIDHASH with a different origin was removed from this
  code; the unmodified `X-Origin` flow is what authenticates successfully.
- **Enrollment is accepted as-is — for now.** Google's backend *can* tell
  this build apart from the official extension: the extension ID differs,
  the manifest is MV2, and the Chrome-only attestation fields are simply
  absent (never fabricated — Google's backend receives a Firefox-shaped
  profile, not a spoofed Chrome one). Google currently accepts that data,
  but could reject or block this configuration at any time. Your device
  appears in the admin console like any other Endpoint Verification client.
  Use it only on devices and accounts where that is appropriate — e.g.
  your own Workspace domain.

## SBOM

[`sbom.spdx.json`](sbom.spdx.json) is an SPDX 2.3 software bill of
materials enumerating every component and its license, including the
third-party libraries compiled *inside* Google's minified bundle:
Closure Library (Apache-2.0), asn1js and pkijs (BSD-3-Clause),
moment.js (MIT), and a MochiKit-derived Deferred (MIT). File-level
SHA256 checksums are included. It is validated on every CI run.

## Verification

The compiled files in this repo are derived from the official Chrome
extension. As of the current release of this port:

- **Official listing:** Chrome Web Store item
  [`callobklhcbilhphinckomhgkigmfocg`](https://chromewebstore.google.com/detail/endpoint-verification/callobklhcbilhphinckomhgkigmfocg)
  ("Endpoint Verification", Google LLC), version **1.140.0**.
- **CRX download** (Google's signed update service):

  ```sh
  curl -fsSL -o ev.crx \
    "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=138.0.0.0&acceptformat=crx2,crx3&x=id%3Dcallobklhcbilhphinckomhgkigmfocg%26uc"
  # CRX used for the current snapshot:
  # SHA256: 617bdda6bc41ac9e177691d489c22de458fa38bd738e792d964c61b99c151eed
  ```

  The pinned SHA256 makes `verify.sh` — and the weekly CI run — **fail
  loudly** once Google ships a new version. That is the intended staleness
  signal, not a bug: re-derive the port from the new CRX and update
  `VERSION` / `KNOWN_CRX_SHA256` in `verify.sh`.

- **Extract the CRX** (it is a ZIP payload behind a CRX3 header):

  ```sh
  python3 -c "import zipfile,io;d=open('ev.crx','rb').read();zipfile.ZipFile(io.BytesIO(d[d.index(b'PK\x03\x04'):])).extractall('official/')"
  ```

- **Diff against this repo.** The following files are byte-identical to the
  official CRX (verified for the 1.140.0 snapshot):

  `background_service_worker.js`, `popup_script.js`, `options_script.js`,
  `log_script.js`, `offscreen_script.js`, `mdl_all_js_compiled.js`,
  `iframe_sandbox.html`, `log.html`, `options.html`, `log.css`,
  `options.css`, `material_design_lite.css`, `popup.css`, `css/**`

- **Intentional differences from the official package:**
  - `manifest.json` — converted from MV3 (service worker) to Firefox MV2
    (event page); Chrome-only manifest sections (`oauth2`, `sandbox`,
    enterprise permissions) are dropped or replaced by
    `browser_specific_settings`; the MV2 CSP string replaces the MV3 CSP
    object. `browser_specific_settings.gecko.data_collection_permissions`
    (`authenticationInfo`, `personallyIdentifyingInfo`) is added per
    Firefox's built-in data-consent manifest key (required for new
    extensions since November 2025); the display `name` is shortened to
    fit AMO's 45-character limit.
  - `popup.html` — the Google logo `<img>` was removed (trademark; the
    logo assets in `googlelogo/` are not redistributed).
  - `_locales/en/messages.json` — JSON key ordering only; content is
    semantically identical.
  - Added port files: `compat_shim.js`, `setup-native-host.sh`,
    `README.md`, `NOTICE`, `LICENSE`, `.gitignore`.
  - Not carried over from the CRX: `background.html` (a vestigial file
    referencing two scripts that are not shipped in the CRX itself; the MV3
    manifest uses a service worker instead).

## Caveats — no guarantees

- **No warranty.** Apache-2.0 §7-8 applies in full: this is an
  experimental port of an unsupported configuration. It can break at any
  time, e.g. when Google rotates the extension or changes the backend.
- **Manifest V2 sunset.** The port uses MV2 (Google's compiled code assumes
  an event page / service worker; Firefox MV2 still runs it). Mozilla's MV2
  deprecation timeline applies — expect this to need rework eventually.
- **Google ToS.** Running this modified-package configuration against
  Google's services, and redistributing the compiled extension, may
  intersect Google's Terms of Service. You assume that risk.
- **macOS only.** The native-host setup script covers macOS. Linux and
  Windows ports would need equivalent manifests and helper installs.
- **Not for sneaking past admins.** If your organization uses device
  verification, the point of this port is *compliance on a browser Google
  doesn't support* — not evading visibility.

## License

Apache-2.0 (see [LICENSE](LICENSE)). The compiled Google components
retain their upstream copyright notices; port-specific additions are
copyright their respective authors. See [NOTICE](NOTICE) for the full
provenance and trademark statement.
