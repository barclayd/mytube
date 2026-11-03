# MyTube's YouTubeKit patch

Source: https://github.com/alexeichhorn/YouTubeKit

Upstream revision: `7f75a2299dc329c0b7855afb25d47663a02855cb`

The upstream `Sources`, `Package.swift` and MIT `LICENSE` are preserved here, with one source change in `Extraction.findObjectFromStartpoint`. No extraction proxy or alternative backend is added.

The video `3zR_oU1C94Q` includes a standalone Unicode combining mark (`U+A92C`) in its metadata tags. Swift's `Character` combines that mark with the preceding JSON quote. The original scanner misses the quote, consumes subsequent JavaScript, and reports `regexMatchError` despite valid JSON and an `OK` playability status.

The patched scanner walks UTF-8 bytes to recognise JSON's ASCII delimiters independently of grapheme clusters. It retains nested object/array and escape handling, and rejects incomplete or mismatched input. Availability checks, signature solving, stream selection and DRM filtering are unchanged.

The regression test fails against the unmodified upstream parser. Run the offline tests with:

```sh
swift test --package-path Vendor/YouTubeKit
```

When updating the dependency, compare this directory to the new upstream source. Remove the local package and return `project.yml` to a remote pin when upstream contains an equivalent tested fix.
