# MyTube

A minimal native YouTube download library for iOS 27, built with SwiftUI and [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit).

Tap Paste & Download in the tab bar to immediately save a copied YouTube link. To enter or review a URL first, tap Add Video, paste a video or Shorts link, then tap Download Video. Select the saved video to play it offline. Swipe a download to delete it, or touch and hold to share its local MP4. Search appears once the library has content.

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

YouTubeKit is pinned to a reviewed source revision in `project.yml` and `Package.resolved`.

## Downloads

- Uses YouTubeKit's local extraction; no third-party remote extraction proxy
- Chooses the highest-resolution natively playable MP4 containing both video and audio; separate audio/video streams and live HLS are not merged or downloaded
- Waits for YouTubeKit's stream availability time before requesting media
- Reports extraction and HTTP failures; keeps the entered URL available for retry
- Shows transfer progress when the server provides a content length; supports cancellation
- Validates playback before adding a video to the library and removes partial files on failure
- Stores an atomic JSON index, MP4s and generated thumbnails in Documents/Videos, excluded from iCloud backups
- Continues briefly in the background using the system's finite task allowance; interrupted downloads must be restarted (no resumable background transfer service)

YouTube changes its unofficial interfaces frequently, and extraction can fail by video, region or network. Age-restricted, private, protected and account-only media are not supported. Download availability and maximum quality depend on the streams YouTube exposes.

## Checks

Unit tests cover recognised URL formats, invalid and deceptive hosts, restoring the library, missing media, corrupt indices and deletion persistence. Simulator evidence is attached to the pull request. Device signing, TestFlight delivery and real-device testing are not configured in this new repository.
