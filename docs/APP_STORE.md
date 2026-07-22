# App Store Connect Copy

This document is the source of truth for Resonance's Mac App Store listing.
Copy the English text exactly unless a later release changes the app's behavior.

## App information

| Field | Value |
| --- | --- |
| Name | `Resonance: Music Sync` |
| Subtitle | `Sync to the Music Around You` |
| Primary category | Music |
| Secondary category | Utilities |
| Content rights | The app accesses third-party content through Apple's MusicKit and Apple Music services, and the developer has the necessary rights to use those services. |
| License agreement | Apple Standard EULA |

## Pricing and availability

| Field | Value |
| --- | --- |
| Base storefront | United States |
| Price | `US$4.99` or the nearest available price point |
| In-App Purchases | None |
| Release method | Manual release |
| Distribution | Public App Store; select the intended storefronts |
| Tax category | App Store software |

The purchase is for Resonance's music-recognition-to-playback synchronization
utility. It does not sell or unlock Apple Music content. Playback uses the
customer's existing Apple Music subscription.

## URLs

| Field | Value |
| --- | --- |
| Support URL | `https://github.com/JacobLinCool/Resonance/issues` |
| Marketing URL | `https://github.com/JacobLinCool/Resonance` |
| Privacy Policy URL | `https://github.com/JacobLinCool/Resonance/blob/main/PRIVACY.md` |

## Promotional text

```text
Hear music playing nearby? Resonance identifies it and starts your Apple Music playback at the matching moment.
```

## Description

```text
Resonance is a macOS menu bar utility that identifies music playing nearby and starts the corresponding song from your Apple Music subscription at the matching moment.

It is designed for shared spaces such as cafés, studios, offices, and parties. When you want to continue listening on your own headphones or speakers, choose Enable. Resonance listens for a recognizable song, identifies it with ShazamKit, and synchronizes Apple Music playback to the part you are currently hearing.

FEATURES

• Identifies nearby music from the menu bar
• Starts the corresponding Apple Music song at the matching position
• Follow the room: optionally keeps listening during playback, switching automatically when the room changes songs and correcting drift
• Keeps a recognition history with artwork and Open in Apple Music links
• Compensates for audio-output latency, re-measured when you switch output devices
• Provides a manual ±500 ms sync adjustment, saved per output device
• Posts an optional notification when a match starts playing
• Optional global shortcuts and open-at-login
• Runs as a lightweight, sandboxed macOS app

CONTROLS

Enable requests the required permissions and starts listening. After a match, microphone recognition stops and Apple Music playback begins.

Disable stops recognition and any Apple Music playback started by Resonance.

Re-sync stops the current playback and listens again for a fresh match.

REQUIREMENTS

• An active Apple Music subscription
• Microphone and Media & Apple Music permission
• An internet connection for ShazamKit recognition and Apple Music playback

Resonance does not record or retain microphone audio and does not operate developer-controlled servers. Apple Music catalog availability varies by country or region.
```

## What's New (0.2.0)

```text
• Follow the room: Resonance can keep listening while it plays, switching automatically when the room changes songs and correcting timing drift
• Recognition history with artwork and Open in Apple Music links
• Sync adjustment is now saved per audio output device, and switching devices mid-song re-measures latency and re-aligns once
• Artwork, playback progress, and an Open in Apple Music link in the popover
• Optional match notifications, global shortcuts (⌃⌥⌘E / ⌃⌥⌘R), and open-at-login
• First-run welcome window that explains the permission prompts
• Traditional Chinese (zh-Hant) localization
```

## Localizations

The listing and the app are available in English (primary) and Traditional
Chinese. Localize the App Store metadata for `zh-Hant` using translations of
the copy in this document.

## Keywords

The following value is 92 characters, within App Store Connect's 100-character
limit.

```text
music sync,song recognition,menu bar,audio sync,playback,ambient music,Apple Music,ShazamKit
```

## Copyright

```text
2026 JHEN-KE LIN
```

App Store Connect adds the copyright symbol automatically.

## Screenshot plan

Use one supported 16:10 Mac screenshot size consistently. `2880 x 1800` is the
preferred source size.

1. **Sync to the music around you** — Show Resonance actively recognizing music.
2. **Catch up at the matching moment** — Show a recognized title and active playback.
3. **Fine-tune the timing** — Show the sync adjustment control and settings window.

Do not use Apple Music artwork as a decorative marketing asset. Artwork may
appear only when it is part of a genuine screenshot of music playback.

## App privacy answers

For the current implementation:

- Privacy Policy URL: use the URL above.
- Data collection: **No, we do not collect data from this app.**
- Tracking: **No.**
- User Privacy Choices URL: leave blank.

Resonance processes microphone audio in real time through Apple's ShazamKit,
uses MusicKit for catalog lookup and playback, and saves its preferences and
the on-device recognition history (song titles, artists, artwork URLs, and
timestamps — never audio) locally in `UserDefaults`. It has no
developer-controlled backend, analytics, advertising, accounts, or long-term
audio storage. Revisit these answers before every release if any of those
facts change.

The bundled `PrivacyInfo.xcprivacy` declares no tracking or collected data. It
declares the approved required-reason API uses for app-only `UserDefaults`
preferences (`CA92.1`) and monotonic elapsed-time calculations (`35F9.1`).

## Export compliance

The app does not implement proprietary or non-exempt encryption. It relies on
encryption supplied by Apple's operating system and services. The build declares
`ITSAppUsesNonExemptEncryption` as `false`.

## App Review information

### Sign-in required

No Resonance account or demo credentials are required. Testing synchronized
playback requires a review device signed in to an active Apple Music subscription.

### Review notes

```text
Resonance is a macOS menu bar utility. The App Store purchase is for Resonance's recognition-to-timeline synchronization functionality; the app does not sell, unlock, or provide an Apple Music subscription or Apple Music content. Playback uses the reviewer's existing Apple Music subscription.

To test:
1. Sign in to Apple Music on the review Mac with an account that can play catalog content.
2. Play a commercially released song from a separate phone or speaker near the Mac.
3. Launch Resonance. On first launch a welcome window explains the flow; choose Get Started, or close it and choose Enable from the menu bar icon.
4. Grant Microphone and Media & Apple Music access when prompted.
5. Resonance identifies the nearby song using ShazamKit, stops microphone recognition, and starts the corresponding Apple Music catalog song at the estimated matching position.
6. During playback, Re-sync stops the current song and returns to recognition. Disable stops recognition and any playback started by Resonance.

The app does not record or retain microphone audio and sends no data to developer-controlled servers. Network access is used only by Apple frameworks for ShazamKit recognition and MusicKit/Apple Music catalog playback.
```

### Contact

Use the Account Holder's current name, email address, and phone number. These
fields are not public.

## Final submission checklist

- Paid Apps Agreement, banking, and tax information are active.
- Price and storefront availability are configured.
- Age-rating answers account for the possibility that catalog music contains
  explicit language or mature themes.
- App privacy answers are published.
- At least one valid Mac screenshot is uploaded.
- The processed build has no unresolved compliance warning.
- Review contact information and the review notes above are present.
- The correct build is selected and manual release is enabled.
