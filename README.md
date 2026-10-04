# Rupick

Your Xcode asset companion. Open a project folder to discover exact duplicate content among existing image assets. Inspect group members and their representations side by side, or choose or drop incoming PNG or JPEG images to compare with the project. All analysis runs locally, and project assets are read only.

Requires an Apple silicon Mac running macOS 15 or later and Xcode with Swift 6 support. Open `rupick.xcodeproj`, select the `rupick` scheme, and run on My Mac. Local builds use ad-hoc signing; no developer account is needed. See [the implementation decision](docs/adr/0001-native-exact-image-comparison.md) for sandbox, colour, orientation, and decoding policies.

The search recursively discovers `.imageset` entries inside `.xcassets` within the selected folder, including nested projects and packages. It respects project-local `.gitignore` rules, prunes ignored directories and `.git` metadata, and does not follow symbolic links. Intentional ignore exclusions do not mark the scan incomplete. Each catalog entry is a separate result, even when asset names repeat. Duplicate groups contain at least two distinct catalog entries; repeated representations within one asset do not form a group. Equal content does not establish that assets are interchangeable or safe to delete. The representation picker identifies every exact variant and exposes scale and appearance alternatives.

Adding incoming images keeps your current inspection open; select an incoming image in the sidebar to inspect its matches. Batches retain their submission order, even when file loading finishes out of order. Opening a project folder again starts a fresh session. Catalog changes retain inspection where possible; a removed or changed exact match clears its recorded reuse decision.

Progress and provisional matches appear while background work continues. Cancelled searches and skipped or unreadable images remain visibly incomplete. PNG and JPEG representations are supported; PDF, SVG, and other formats are reported as skipped. This milestone does not detect resized copies or changes to transparent padding. Catalog changes update comparisons and previews automatically while the project is open. Bursts of edits are coalesced, and results remain provisional until the latest scan completes. Restored sessions are a subsequent milestone.

For each incoming image, choose **Reuse This Asset** on an exact matching representation or **Keep as New**, even when matches exist. The sidebar shows reviewed and unreviewed images, and the review card retains the chosen catalog location and image file. Decisions and representation selections remain available while navigating and adding images within the same project session. Opening a project folder again resets them. Decisions never import or modify assets; comparison results remain visible independently.

Run the tests:

```sh
xcodebuild test -scheme rupick -destination 'platform=macOS' -derivedDataPath /tmp/rupick-build
```

The native UI tests exercise mixed PNG/JPEG batches through multiple selection and Finder drops, isolate decoding failures, navigate the incoming list, and retain incomplete-scan status. They drive the real folder and image panels, checks same-named entries in different catalogs, verifies side-by-side previews, and selects a dark scale alternative. Project-session tests cover pixel, transparency, JPEG, orientation, boundary, error, cancellation, and provisional-result behavior. See [acceptance validation](docs/acceptance.md) for repeatable fixtures and optional local project checks.
