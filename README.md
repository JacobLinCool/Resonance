# Resonance

Resonance is a macOS menu bar app that identifies nearby music with ShazamKit,
starts the matching Apple Music track near the detected position, and corrects
the remaining player-timeline offset. Click **Enable**, put on your headphones,
and catch up to the room.

## Install

Resonance requires:

- macOS 26 or later on Apple silicon or Intel
- an active Apple Music subscription
- microphone access and an internet connection

Resonance is distributed through two channels with the same feature set:

- **Mac App Store:** paid listing named
  [**Resonance: Music Sync**](https://apps.apple.com/tw/app/resonance-music-sync/id6791231331).
- **GitHub Releases:** free Developer ID-signed, notarized DMG and ZIP.
  Direct-download builds check GitHub once a day and show a download link in
  the popover and settings when a newer release exists; App Store copies update
  through the App Store.

To install the direct-download release:

1. Download the DMG and `SHA256SUMS` from
   [GitHub Releases](https://github.com/JacobLinCool/Resonance/releases).
2. Optional but recommended: put both files in the same folder and verify the
   download:

   ```sh
   shasum -a 256 -c SHA256SUMS --ignore-missing
   ```

3. Open the DMG and drag **Resonance** to **Applications**.
4. Launch Resonance. It appears in the menu bar, not the Dock.

Release artifacts are universal, Developer ID-signed, notarized, and stapled.
An ad-hoc build from source can validate the UI, but ShazamKit recognition and
MusicKit playback require a signed App ID with both services enabled.

## First use

On the first launch, a welcome window explains the listen → recognize → sync
flow and which permissions are about to be requested. **Get Started** triggers
the permission prompts immediately; **Not Now** leaves Resonance idle in the
menu bar. Afterwards:

1. Click the Resonance icon in the menu bar.
2. Click **Enable**.
3. Allow **Microphone** access, then **Media & Apple Music** access.
4. Play music nearby. Resonance starts recognition after the level crosses the
   loudness threshold.

If the menu bar is too crowded to show the Resonance icon, launch Resonance
again from Spotlight, Finder, or Applications. The running app opens a
standalone control window with the same state and controls as the menu bar.

If you previously denied either request, enable Resonance in:

- **System Settings › Privacy & Security › Microphone**
- **System Settings › Privacy & Security › Media & Apple Music**

The default threshold is `-50 dBFS`. Move it left for quieter rooms or right if
background noise triggers recognition too easily.

Click the gear button to open **Settings and Help**, which explains every
control, lists the playback requirements, and provides the
[Privacy Policy](PRIVACY.md) and support links.

The **Sync adjustment** slider is always available and adds a `-500 ms` to
`+500 ms` manual trim on top of Resonance's built-in `+200 ms` playback offset.
Therefore, the displayed `+0 ms` means an effective `+200 ms` base offset, and
displayed `+50 ms` means `+250 ms`, before output-device latency is added. If
Resonance sounds late, move it right; if it sounds early, move it left. The
committed value is saved separately for each audio output device — AirPods and
built-in speakers need different trims — and restored when the system default
output changes. During playback, dragging only previews the value and releasing
the slider applies one seek. Switching the default output device mid-playback
also re-reads the new device's reported latency and applies one corrective seek.

**Follow the room** keeps the microphone in play while a synced song runs in
your headphones: every ~25 seconds, and again near the end of the track, a
short probe re-runs recognition against the room. A different song switches
playback automatically; the same song is re-aligned when the measured drift
exceeds 350 ms; an unrecognizable room leaves playback untouched. The mode is
off by default and can be enabled from the popover or Settings.

Every recognized song is stored in the **History** window (clock icon in the
popover) with its artwork, recognition time, and an Open in Apple Music link.
The list keeps the last 100 songs locally; consecutive re-recognitions of the
same song within ten minutes collapse into one entry. **Match notifications**
(on by default, Settings toggle) post a "Now syncing" notification when a
match starts playing. **Global shortcuts** (off by default) map ⌃⌥⌘E to
Enable/Disable and ⌃⌥⌘R to Re-sync systemwide, and **Open at login** starts
Resonance with your Mac.

## How it works

| State | Behavior |
| --- | --- |
| **Disabled** | Microphone capture and background polling are stopped. |
| **Active** | Crossing the threshold starts the recognition stream. The gate remains open through brief quiet passages, then closes after about 2.5 seconds. |
| **Starting** | Recognition is stopped while MusicKit prepares the matched catalog track. |
| **Playing** | The matched Apple Music track plays while microphone capture and recognition are stopped. With Follow the room enabled, short periodic probes reopen the microphone to detect song changes and drift. |

After a match, Resonance prebuffers and positions the Apple Music entry before
playback. It advances that position by the default output device's reported
Core Audio pipeline latency, including the device, safety offset, I/O buffer,
and active output stream. It then extrapolates the reference position with
monotonic time and ShazamKit's frequency-skew estimate, filters three
timestamped player readings, and targets a logical timeline error within 30 ms.
If needed, it makes at most one startup correction, then leaves playback
uninterrupted. The microphone is off during this phase, so crowd noise and
Resonance's own playback cannot move the synchronization target.

The fixed `+200 ms` offset, measured output latency, and manual sync adjustment
are added everywhere Resonance calculates a playback target, including startup.
Moving the slider during playback cancels any unfinished automatic startup
correction before the new value is applied once.

This controller aligns MusicKit's reported timeline and compensates the output
latency reported by Core Audio. It does not acoustically measure the signal at
the speaker or headphones, so 30 ms remains a logical target rather than a
promise of sub-30 ms acoustic alignment. Compensation is limited to what the
current audio driver reports.

Click **Re-sync** to stop playback and listen for a fresh match. Click
**Disable** to stop capture, recognition, playback, and polling immediately.

## Troubleshooting

**There is no Dock icon.** Resonance stays out of the Dock and normally opens
from the waveform icon at the top-right of the screen. Launching the running
app again opens the standalone control window.

**The menu bar icon is missing.** macOS can temporarily hide menu bar items when
space is limited. Launch Resonance again from Spotlight, Finder, or Applications
to open its standalone control window. When the icon is visible, hold Command
and drag it toward the right to give it a more accessible position.

**Recognition does not start.** Confirm microphone access, an internet
connection, and a threshold below the live meter level. Source builds must also
use an explicit App ID with ShazamKit enabled.

**A song is recognized but does not play.** Confirm **Media & Apple Music**
access, sign in to Apple Music, and verify that the subscription can play catalog
content. A source build also needs MusicKit enabled for its exact App ID.

**The app reports a signing or service error.** Install the notarized release,
or follow the signed development setup below. Rebuilding ad hoc cannot repair an
App Services configuration.

## Uninstall

Quit Resonance and move `/Applications/Resonance.app` to the Trash. To also
reset its privacy decisions:

```sh
tccutil reset Microphone dev.jacoblincool.Resonance
tccutil reset MediaLibrary dev.jacoblincool.Resonance
```

For a source installation, use the same bundle ID and install directory used at
install time:

```sh
BUNDLE_ID=com.example.Resonance \
INSTALL_DIR="$HOME/Applications" \
  make uninstall
```

The uninstall script checks the existing app's bundle ID before deleting it.

## Build from source

### Compile and test

Install Xcode 26 or later and [Homebrew](https://brew.sh), then run:

```sh
make setup
make test
make build
```

`make setup` installs XcodeGen through Homebrew when needed and generates
`Resonance.xcodeproj`. The generated project is ignored by Git; `project.yml` is
the source of truth.

### Run a working development build

Catalog recognition and playback need a team enrolled in the Apple Developer
Program:

1. Register a unique **explicit App ID** in Certificates, Identifiers & Profiles.
2. In its **App Services** tab, enable **ShazamKit** and **MusicKit**.
3. Add the corresponding Apple Developer account to Xcode.
4. Pass the exact team ID and bundle ID when building:

   ```sh
   export DEVELOPMENT_TEAM=ABCDE12345
   export BUNDLE_ID=com.example.Resonance

   make run
   # Or install the signed Release build:
   make install
   ```

The bundle ID must exactly match the App ID. Xcode handles development
provisioning automatically. See Apple's setup guides for
[ShazamKit](https://developer.apple.com/help/account/services/shazamkit/) and
[MusicKit](https://developer.apple.com/help/account/services/musickit/).

`make install` defaults to `/Applications` and launches the app. Override either
behavior explicitly:

```sh
INSTALL_DIR="$HOME/Applications" LAUNCH=0 make install
```

Unlike `make run`, `make install` refuses to create an ad-hoc installation.

### Development checks

Install the complete validation toolchain once:

```sh
brew install actionlint shellcheck swiftlint xcodegen
```

Then use:

| Command | Purpose |
| --- | --- |
| `make check` | Run formatting, SwiftLint, shell/workflow checks, tests, and a Debug build. |
| `make test` | Run the hosted unit-test target with coverage enabled. |
| `make build` / `make release` | Build Debug for the current Mac or universal Release for arm64 and x86_64. |
| `make run` | Build and launch; pass `DEVELOPMENT_TEAM` and `BUNDLE_ID` for working services. |
| `make install` / `make uninstall` | Install or remove an exact, bundle-ID-checked path. |
| `make package` | Create a validated `.app`, `.zip`, `.dmg`, and `SHA256SUMS` in `dist/`. |
| `make app-store-archive` | Create and validate a signed `AppStore` archive. |
| `make app-store-upload` | Cloud-sign and upload an archive to App Store Connect. |
| `make clean` | Remove the generated project and local build/package output. |

To build signed distribution artifacts locally:

```sh
SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="notarytool-profile" \
  make package
```

Without both distribution credentials, `make package` produces validation-only
artifacts, prints a warning, and adds `dist/VALIDATION_ONLY` to distinguish them
from a release. See [docs/RELEASING.md](docs/RELEASING.md) for the complete
release process and [docs/APP_STORE.md](docs/APP_STORE.md) for the canonical
App Store Connect copy.

## Architecture

| File | Responsibility |
| --- | --- |
| `AppDelegate.swift` | App lifecycle: shared coordinator, reopen handling, onboarding, shortcuts, update checks, and window controllers. |
| `AppCoordinator.swift` | Main-actor state machine, authorization, and service transitions. |
| `AppCoordinator+FollowRoom.swift` | Follow-the-room probe loop: song-change switching and drift correction during playback. |
| `AppCoordinator+Adjustment.swift` | Per-device sync adjustment persistence and default-output-device change handling. |
| `AudioMonitor.swift` | AVAudioEngine tap, multichannel RMS meter, atomic threshold, and hysteresis gate. |
| `ShazamRecognizer.swift` | Streaming SHSession wrapper with synchronized session replacement and stale-result rejection. |
| `MusicPlayer.swift` | Authorization, serialized startup, cancellation rollback, playback, seeking, and latency refresh. |
| `MusicPlayerBackend.swift` | Main-actor MusicKit adapter, catalog loading, subscription checks, and type erasure for tests. |
| `Models.swift` | Sendable recognition values and monotonic position extrapolation. |
| `MatchHistory.swift` | Bounded, persisted recognition history with duplicate collapsing. |
| `MatchNotifier.swift` | Local "Now syncing" notifications with lazy authorization. |
| `OutputLatency.swift` | Converts Core Audio device, stream, safety, and buffer latency into playback lead time. |
| `OutputDeviceObserver.swift` | Core Audio default-output-device identity and change notifications. |
| `LoginItem.swift` | SMAppService launch-at-login registration and its observable toggle model. |
| `HotKeyCenter.swift` | Sandbox-safe Carbon global hot keys and the shortcuts settings model. |
| `UpdateChecker.swift` | GitHub latest-release comparison for direct-download builds. |
| `PlaybackSessionController.swift` | Bounded startup alignment, one-shot manual adjustment, fresh-match adoption, and playback-end watching. |
| `PlaybackSynchronization.swift` | Timestamped error measurement, robust filtering, and bounded startup-correction policy. |
| `ContentView.swift` | Menu-bar popover: artwork, progress, live meter, threshold, sync adjustment, follow toggle, and controls. |
| `HistoryView.swift` | Recognition history window with artwork and Apple Music links. |
| `OnboardingView.swift` | First-run walkthrough shown before any permission prompt. |
| `SettingsView.swift` | General settings, update checks, requirements, control explanations, privacy disclosure, and support links. |

## License

[MIT](LICENSE)

Inspired by [coffee-music](https://github.com/Buffett111/coffee-music);
Resonance brings the same “catch up to the room” idea to ShazamKit and MusicKit.
