# MyTube

A minimal native YouTube download library for iOS 27, built with SwiftUI and [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit).

Tap the clipboard icon above Search in the native Duo toolbar to immediately save a copied YouTube link. To enter or review a URL first, tap Add Video, paste a video or Shorts link, then tap Download Video. Select the saved video to play it offline. Swipe a download to delete it, or touch and hold to share its local MP4. Search appears once the library has content.

## Design

System typography, semantic colours, native Liquid Glass controls and an inset grouped library. A focused Add Video sheet keeps URL entry separate from browsing, with a labelled download action and inline validation. A compact progress panel appears only during downloads. iPhone Duo uses the same persistent selection and download state across folding: a compact library on the cover and a library/player split when sufficient width is available. Standard navigation adapts to rotation, Dynamic Type, dark appearance, VoiceOver and reduced motion.

## Build

Requires Xcode 27.2 and iOS 27.0 or later. Open `MyTube.xcodeproj` and choose the `MyTube` scheme. Set your development team to run on a physical device.

The checked-in project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project MyTube.xcodeproj -scheme MyTube \
  -destination 'platform=iOS Simulator,name=MyTube Duo' test CODE_SIGNING_ALLOWED=NO
```

YouTubeKit is vendored at `Vendor/YouTubeKit` from revision `7f75a2299dc329c0b7855afb25d47663a02855cb`, with a JSON parsing fix for Unicode combining marks. See its `MYTUBE-PATCH.md` for the upstream source, patch and regression checks.

## Downloads

- Uses a private Cloudflare-hosted YouTubeKit server for configured personal builds; extraction and video/audio transfers run through Cloudflare
- Uses YouTubeKit’s local → remote fallback when no private extractor is configured; local metadata failures do not stop fallback
- Downloads one video at a time, rejects duplicates without querying YouTube and discards old batch checkpoints
- Defaults to Full HD (up to 1080p), with persistent 360p, 720p, 1080p and 4K (2160p) choices in Add Video; the clipboard action uses the same preference
- Selects the best available compatible MP4 video and AAC audio, downloading separate tracks when needed and combining them without re-encoding
- Shows the actual saved resolution; source availability and device codec support can limit the requested quality
- Does not download live HLS streams
- Waits for YouTubeKit's stream availability time before requesting media
- Reports extraction and HTTP failures; keeps the entered URL available for retry
- Shows transfer progress when the server provides a content length; supports cancellation
- Validates playback before adding a video to the library and removes partial files on failure
- Stores an atomic JSON index, MP4s and generated thumbnails in Documents/Videos, excluded from iCloud backups
- Uses `BGContinuedProcessingTask` for the whole user-started download, including extraction, transfers and remuxing, with system progress and cancellation while the screen is locked
- Keeps working files accessible after the first device unlock; if iOS denies background execution, shows a keep-open message and uses only a short cleanup allowance
- Remains subject to iOS resource limits and force-quit cancellation; resuming restarts the interrupted video's transfer (no byte-range resume)

The player uses AVKit’s native full-screen, transport, AirPlay and Picture in Picture controls, with background audio and safe-area insets to give the controls room inside the player. PiP can continue when leaving the app, subject to iOS support and the user’s PiP settings.

YouTube changes its unofficial interfaces frequently, and extraction can fail by video, region or network. Age-restricted, private, protected and account-only media are not supported. Download availability and maximum quality depend on the streams YouTube exposes.

## Checks

Unit tests cover recognised URL formats, invalid and deceptive hosts, library persistence, resolution selection and combining a 1920×1080 video track with audio without reducing resolution. Parser regression tests run separately with `swift test --package-path Vendor/YouTubeKit`. Simulator evidence is attached to the pull request. Development builds can be signed with a locally selected team and installed directly on a connected device. TestFlight delivery is not configured.

## Private extractor

The personal build uses [the MyTube server fork](https://github.com/barclayd/YouTubeKit-Server) at `https://mytube-extractor.barclaysd.workers.dev`. The server requires authentication and issues short-lived signed media links. It can still encounter YouTube restrictions.

`MyTube/Build.xcconfig` optionally includes the ignored `MyTube/PrivateRemote.xcconfig`. Define `MYTUBE_REMOTE_URL` (write the scheme as `https:/$()/` in xcconfig) and `MYTUBE_REMOTE_TOKEN` there before building. The token authenticates only the WebSocket request to the private Worker; it is not forwarded to YouTube. A personal build embeds this token in its app bundle. Do not commit the private file or use this shared-token model for wider distribution.

YouTubeKit’s vendored changes add remote request headers and stream titles, propagate remote errors, and keep local availability/metadata checks from blocking remote-only extraction.

The [local token-provider trial](docs/token-provider-trial.md) records a successful 1080p download with yt-dlp and bgutil, including reproduction steps and the remaining backend integration work.
