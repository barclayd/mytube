# MyTube's YouTubeKit patch

Source: https://github.com/alexeichhorn/YouTubeKit

Upstream pull request: https://github.com/alexeichhorn/YouTubeKit/pull/151

Upstream revision: `7f75a2299dc329c0b7855afb25d47663a02855cb`

The upstream `Sources`, `Package.swift` and MIT `LICENSE` are preserved here, with the JSON scanner fix and explicit handling for YouTube’s sign-in challenges. No extraction proxy or alternative backend is added.

The video `3zR_oU1C94Q` includes a standalone Unicode combining mark (`U+A92C`) in its metadata tags. Swift's `Character` combines that mark with the preceding JSON quote. The original scanner misses the quote, consumes subsequent JavaScript, and reports `regexMatchError` despite valid JSON and an `OK` playability status.

The patched scanner walks UTF-8 bytes to recognise JSON's ASCII delimiters independently of grapheme clusters. It retains nested object/array and escape handling, and rejects incomplete or mismatched input. Signature solving, stream selection and DRM filtering are unchanged.

`Extraction.checkForRequestBlock` preserves an explicit `LOGIN_REQUIRED` response whose reason asks the viewer to confirm they are not a bot. `YouTube.videoInfos` raises `requestBlocked` when no client returns usable metadata, instead of discarding those responses and raising a generic extraction error. A usable response from another client is preserved. This reports the server restriction; it does not bypass sign-in or add authentication. MyTube uses the error to pause the upgrade queue instead of failing every remaining video. The additional request-block reporting change is local; upstream PR #151 contains only the JSON scanner fix.

The regression test fails against the unmodified upstream parser. Run the offline tests with:

```sh
swift test --package-path Vendor/YouTubeKit
```

When updating the dependency, compare this directory to the new upstream source. Remove the local package and return `project.yml` to a remote pin when upstream contains an equivalent tested fix.
