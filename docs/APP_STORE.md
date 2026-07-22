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
Chinese. The `zh-Hant` metadata below is the canonical translation of the
English copy in this document.

### zh-Hant subtitle

```text
與身邊的音樂同步
```

### zh-Hant promotional text

```text
聽到附近正在播放的音樂？Resonance 會辨識它，並讓你的 Apple Music 從相同的位置接著播放。
```

### zh-Hant description

```text
Resonance 是一款 macOS 選單列工具程式，能辨識附近正在播放的音樂，並透過你的 Apple Music 訂閱，從對應的位置開始播放同一首歌。

它專為咖啡廳、工作室、辦公室、派對等共享空間設計。當你想改用自己的耳機或喇叭繼續聆聽時，按下「啟用」即可。Resonance 會聆聽可辨識的歌曲，以 ShazamKit 完成辨識，並將 Apple Music 播放同步到你當下聽到的段落。

功能特色

• 從選單列辨識附近的音樂
• 從對應位置開始播放 Apple Music 中的同一首歌
• 跟隨現場：可選擇在播放時持續聆聽，現場換歌時自動切換，並校正時間漂移
• 辨識歷史：保留封面與「在 Apple Music 開啟」連結
• 補償音訊輸出延遲，切換輸出裝置時自動重新測量
• ±500 毫秒手動同步微調，依輸出裝置分別儲存
• 配對的歌曲開始播放時可選擇顯示通知
• 可選的全域快速鍵與登入時啟動
• 輕量、沙盒化的 macOS app

控制項

「啟用」會要求必要權限並開始聆聽。配對成功後，麥克風辨識停止，Apple Music 開始播放。

「停用」會停止辨識以及由 Resonance 啟動的 Apple Music 播放。

「重新同步」會停止目前播放並重新聆聽配對。

系統需求

• 有效的 Apple Music 訂閱
• 「麥克風」與「媒體與 Apple Music」權限
• 網際網路連線（ShazamKit 辨識與 Apple Music 播放）

Resonance 不會錄製或保留麥克風音訊，也不營運開發者伺服器。Apple Music 目錄的可用性依國家或地區而異。
```

### zh-Hant keywords

The following value is 53 characters, within the 100-character limit.

```text
音樂同步,歌曲辨識,選單列,音訊同步,播放,環境音樂,Apple Music,ShazamKit,聽歌辨曲
```

### zh-Hant What's New (0.2.0)

```text
• 跟隨現場：Resonance 可在播放時持續聆聽，現場換歌時自動切換，並校正時間漂移
• 辨識歷史：保留封面與「在 Apple Music 開啟」連結
• 同步微調現在依音訊輸出裝置分別儲存；播放中切換裝置會重新測量延遲並重新對齊一次
• 選單列面板加入封面、播放進度與「在 Apple Music 開啟」連結
• 可選的配對通知、全域快速鍵（⌃⌥⌘E／⌃⌥⌘R）與登入時啟動
• 首次啟動的歡迎導覽，先說明權限用途
• 正體中文介面
```

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
