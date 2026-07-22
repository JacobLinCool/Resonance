# Releasing Resonance

Resonance ships the same feature set through two macOS distribution channels:

| Channel | Signing and delivery | Price |
| --- | --- | --- |
| GitHub Releases | Developer ID, notarized and stapled DMG/ZIP | Free download |
| Mac App Store | App Sandbox, Apple Distribution, App Store Connect | Paid, approximately US$4.99 |

Both variants use bundle ID `dev.jacoblincool.Resonance`, the same version
number, the same source code, and the same sandbox entitlements. A person who
switches distribution channels may be asked for Microphone and Media & Apple
Music access again because macOS evaluates privacy grants against the app's
distribution signature.

Releases are created only from strict `vX.Y.Z` tags. The tag provides
`CFBundleShortVersionString`; the GitHub Actions run number provides the unique
`CFBundleVersion`.

Direct-download builds check `releases/latest` on GitHub once a day and offer
a download link when the latest tag is newer than the running version. Publish
GitHub releases as full releases with `vX.Y.Z` tags — prerelease or
non-numeric tags are ignored by the in-app check.

## Apple configuration

The explicit App ID `dev.jacoblincool.Resonance` must belong to the signing
team and have the **ShazamKit** and **MusicKit** App Services enabled.

Create the macOS app record in App Store Connect before the first upload:

| Field | Value |
| --- | --- |
| Name | `Resonance: Music Sync` |
| Platform | macOS |
| Bundle ID | `dev.jacoblincool.Resonance` |
| Suggested SKU | `resonance-macos` |
| Primary category | Music |
| Price | The price point closest to US$4.99 |

App Store pricing is product metadata, not a build setting. Configure it under
**Pricing and Availability** in App Store Connect. The paid App Store build has
no feature flags or paid-only code paths; it is functionally identical to the
GitHub release.

## Repository secrets

Configure these GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Ten-character team ID that owns the App ID |
| `DEVELOPER_ID_CERT_P12_BASE64` | Base64-encoded Developer ID Application certificate export (`.p12`) |
| `DEVELOPER_ID_CERT_PASSWORD` | Password for the `.p12` |
| `KEYCHAIN_PASSWORD` | Random password for the workflow's temporary keychain |
| `AC_API_KEY_P8_BASE64` | Base64-encoded App Store Connect API key (`.p8`) |
| `AC_API_KEY_ID` | App Store Connect API key ID |
| `AC_API_ISSUER_ID` | App Store Connect issuer ID |

The App Store Connect key must belong to the same team and have permission to
upload builds and use cloud-managed distribution certificates. The workflow
writes credentials only to runner-temporary files with restrictive permissions
and removes them in `always()` cleanup steps.

## Publish both channels

Run the complete local gate before tagging:

```sh
make check
```

Create and push the release tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The tag workflow runs two independent release jobs after the quality gate:

1. Build a universal app, sign it with Developer ID, notarize and staple the
   app and DMG, verify checksums, and publish the GitHub Release.
2. Create an `AppStore` archive, verify its sandbox entitlements and direct
   MusicKit/ShazamKit linkage, cloud-sign it for Apple Distribution, and upload
   it to App Store Connect.

An upload is not an App Review submission. After Apple finishes processing the
build, select it for the matching version in App Store Connect, complete the
required metadata, submit it for review, and use manual or automatic release as
appropriate. Apple review timing means the two public storefront dates cannot
be guaranteed to match exactly.

## Local Mac App Store archive

The canonical archive command requires explicit version and team inputs:

```sh
DEVELOPMENT_TEAM=ABCDE12345 \
APP_VERSION=0.1.0 \
BUILD_NUMBER=2 \
  make app-store-archive
```

Xcode must be signed in to an account that belongs to the team. The command
creates:

```text
dist/app-store/Resonance-0.1.0-2.xcarchive
```

The generated Xcode scheme also uses the `AppStore` configuration for its
Archive action, so the same archive can be inspected in Xcode Organizer.

## Local App Store Connect upload

For deterministic command-line authentication, provide an App Store Connect
API key:

```sh
DEVELOPMENT_TEAM=ABCDE12345 \
APP_VERSION=0.1.0 \
BUILD_NUMBER=2 \
APP_STORE_API_KEY_PATH=/secure/path/AuthKey_KEYID.p8 \
APP_STORE_API_KEY_ID=KEYID12345 \
APP_STORE_API_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
  make app-store-upload
```

The upload command refuses to reuse an existing archive path or omit a version
or build number. Xcode performs automatic provisioning, cloud distribution
signing, App Store validation, symbol upload, and binary upload.

## Local GitHub-style packaging

Create the notarytool profile once:

```sh
xcrun notarytool store-credentials notarytool-profile \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_ID
```

Then package the direct-download artifacts:

```sh
SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="notarytool-profile" \
  make package

(cd dist && shasum -a 256 -c SHA256SUMS)
```

`NOTARY_PROFILE` without `SIGN_IDENTITY` is rejected. Existing `dist/`
artifacts remain intact unless the new package passes every validation step.
