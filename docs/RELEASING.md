# Releasing Resonance

Releases are created only from strict `vX.Y.Z` tags. The release workflow first
runs the same `make check` gate used for pull requests, then builds a universal
arm64/x86_64 app and signs it with the hardened runtime. It submits the app ZIP
for notarization, staples the app, rebuilds the ZIP, then notarizes and staples
the final DMG before publishing verified artifacts and SHA-256 checksums.

## Apple configuration

The explicit App ID `dev.jacoblincool.Resonance` must have the **ShazamKit** and
**MusicKit** App Services enabled. The signing certificate's team must own that
App ID.

Configure these repository secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | Base64-encoded Developer ID Application certificate export (`.p12`). |
| `DEVELOPER_ID_CERT_PASSWORD` | Password for the `.p12`. |
| `KEYCHAIN_PASSWORD` | Random password for the workflow's temporary keychain. |
| `AC_API_KEY_P8_BASE64` | Base64-encoded App Store Connect API key (`.p8`). |
| `AC_API_KEY_ID` | App Store Connect API key ID. |
| `AC_API_ISSUER_ID` | App Store Connect issuer ID. |

The workflow writes these values only to runner-temporary files with restrictive
permissions and deletes the temporary keychain and key files in an `always()`
cleanup step.

## Publish

Before tagging, run the complete local gate:

```sh
make check
```

Create and push the release tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The tag provides `CFBundleShortVersionString`; the GitHub run number provides
`CFBundleVersion`. When the workflow succeeds, the GitHub Release contains the
DMG, ZIP, and `SHA256SUMS`.

## Local packaging

Create the notarytool profile once:

```sh
xcrun notarytool store-credentials notarytool-profile \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_ID
```

Then package:

```sh
SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="notarytool-profile" \
  make package

(cd dist && shasum -a 256 -c SHA256SUMS)
```

`NOTARY_PROFILE` without `SIGN_IDENTITY` is rejected. Existing `dist/` artifacts
remain intact unless the new package passes every validation step.
