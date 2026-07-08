# Windows installer & release code-signing

## `sparta.nsi`

NSIS script that builds the Windows installer (`sparta-<version>-windows-setup.exe`).
Built by `.github/workflows/release.yml`'s "Build Windows installer" step:

```sh
makensis -DVERSION=0.1.0 -DEXE_PATH=sparta.exe sparta.nsi
```

`OUTFILE` defaults to a name in this script's own directory for a plain local
build; the release workflow passes an absolute `-DOUTFILE=...` so the built
installer lands in `build/` instead (see the comment at the top of the `.nsi`
file — a relative `OutFile` resolves against the script's directory, not the
caller's working directory).

## Code-signing & notarization

Release builds (macOS `.zip`/`.app`, the Windows `.exe`, and the Windows
installer built from this directory) are **unsigned by default**. The
`release.yml` workflow has the plumbing wired up to sign and notarize them
automatically — it just needs the certificates below added as **repository
secrets** (Settings → Secrets and variables → Actions → New repository
secret). Until they're all present, the corresponding step logs an
`::notice::` and no-ops; the build still succeeds, just unsigned, exactly as
today.

**This session cannot obtain or provision these for you** — they require a
paid Apple Developer Program membership and a purchased Windows code-signing
certificate, both tied to the maintainer's own identity/organization. Nothing
short of the actual repo owner buying and generating these can turn signing
on.

### macOS: Developer ID signing + notarization

Godot cross-exports macOS from the Linux runner, so signing/notarizing also
runs there — via [`rcodesign`](https://github.com/indygreg/apple-platform-rs)
(the `apple-codesign` project), which reimplements Apple's codesign/notary
tools in a way that doesn't require a Mac. `release.yml` downloads a pinned
`rcodesign` release (`RCODESIGN_VERSION` at the top of the workflow — bump it
if a newer release is needed).

Required secrets, all four together (partial configuration is treated as
"not configured" and the step no-ops):

| Secret | What it is | How to get it |
| --- | --- | --- |
| `MACOS_CODESIGN_P12_BASE64` | Base64 of a Developer ID Application `.p12` certificate | In Keychain Access, export the Developer ID Application certificate (with its private key) as a `.p12`, then `base64 -i cert.p12 \| pbcopy` (or `base64 -w0 cert.p12` on Linux) |
| `MACOS_CODESIGN_P12_PASSWORD` | Password protecting that `.p12` | Whatever password you set when exporting it |
| `MACOS_TEAM_ID` | Apple Developer Team ID (10 characters) | developer.apple.com/account → Membership details |
| `MACOS_NOTARY_API_KEY_JSON` | An App Store Connect API key, pre-encoded into the JSON blob `rcodesign` expects | Create a key at appstoreconnect.apple.com/access/api (needs the "Developer" role or above), download the `AuthKey_<key id>.p8`, then run `rcodesign encode-app-store-connect-api-key <issuer_id> <key_id> AuthKey_<key_id>.p8` locally and paste the JSON it prints as the secret value |

The workflow signs the exported `.app`, re-zips it, then runs
`rcodesign notary-submit --staple` to submit it to Apple's notary service and
staple the resulting ticket — so the shipped `.zip`/`.app` passes Gatekeeper
with no right-click-Open workaround needed.

Because this can't be exercised end-to-end without real credentials, treat
the exact `rcodesign` invocation as a best-effort scaffold based on its
documented CLI — the maintainer should watch the first real signing run
closely and adjust flags if `rcodesign`'s CLI has moved since
`RCODESIGN_VERSION` was pinned.

### Windows: Authenticode signing

Signing also runs on the Linux runner, via
[`osslsigncode`](https://github.com/mtrojnar/osslsigncode) (a Linux-native
Authenticode signer — installed by `apt-get` in the workflow), so no Windows
runner or `signtool` is needed. Both the raw `sparta.exe` and the NSIS
installer built from this directory get signed.

Required secrets, both together:

| Secret | What it is | How to get it |
| --- | --- | --- |
| `WINDOWS_CODESIGN_PFX_BASE64` | Base64 of an Authenticode code-signing certificate (`.pfx`/`.p12`) — an OV or EV certificate from a CA (DigiCert, Sectigo, SSL.com, etc.) | `base64 -w0 cert.pfx` (Linux/macOS) or `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.pfx"))` (PowerShell) |
| `WINDOWS_CODESIGN_PASSWORD` | Password protecting that `.pfx` | Whatever password the CA/export gave it |

An EV certificate is usually held on a hardware token and can't be exported
as a portable `.pfx` at all — if the maintainer's certificate is EV-on-token,
this plumbing (which assumes an exportable `.pfx` reachable via CI secrets)
won't work as-is, and CI-based signing would need a different approach (e.g. a
self-hosted runner with the token attached). An OV certificate exported as a
`.pfx` works with the setup above unmodified.

### What's already actionable vs. genuinely blocked

- **Actionable now, done in this PR:** the CI steps that sign/notarize when
  secrets exist, no-op with a clear log message when they don't, and this
  documentation of exactly which secrets to add.
- **Genuinely blocked on the repo owner:** obtaining the real Apple Developer
  ID certificate + App Store Connect API key, and the real Windows
  code-signing certificate, and adding them as the repo secrets named above.
  No code change can substitute for a real, paid, identity-verified
  certificate.
