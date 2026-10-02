# Rupick

Your Xcode asset companion. Open a project folder, choose incoming PNG or JPEG images, and inspect exact matches beside existing image representations. All analysis runs locally, and project assets are read only.

Requires an Apple silicon Mac running macOS 15 or later and Xcode with Swift 6 support. Open `rupick.xcodeproj`, select the `rupick` scheme, and run on My Mac. Local builds use ad-hoc signing; no developer account is needed. See [the implementation decision](docs/adr/0001-native-exact-image-comparison.md) for sandbox, colour, orientation, and decoding policies.

The search recursively discovers `.imageset` entries inside `.xcassets` within the selected folder, including nested projects and packages. It does not follow symbolic links. Each catalog entry is a separate result, even when asset names repeat. The representation picker identifies every exact variant and exposes scale and appearance alternatives.

Progress and provisional matches appear while background work continues. Cancelled searches and skipped or unreadable images remain visibly incomplete. PNG and JPEG representations are supported; PDF, SVG, and other formats are reported as skipped. This milestone does not detect resized copies or changes to transparent padding. Catalog watching, review decisions, and restored sessions are subsequent milestones.

Run the tests:

```sh
xcodebuild test -scheme rupick -destination 'platform=macOS' -derivedDataPath /tmp/rupick-build
```

The native UI test drives the real folder and image panels, checks same-named entries in different catalogs, verifies side-by-side previews, and selects a dark scale alternative. Project-session tests cover pixel, transparency, JPEG, orientation, boundary, error, cancellation, and provisional-result behavior. See [acceptance validation](docs/acceptance.md) for repeatable fixtures and optional local project checks.
