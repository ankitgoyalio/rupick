# Exact-match and batch acceptance

The agreed seams are the observable `ProjectSession` and the running native macOS app, as specified in #3 and implemented for #4. No matching-helper or cache-layout tests are used.

`fixtures/ExactMatching` is a synthetic project with two catalogs sharing the name Icon, light and dark scale variants, a corrupt catalog, and incoming images covering renamed/re-encoded content, transparent hidden colour, a new visible colour, dimensions, padding, partial alpha, and corruption. Expected results are in `expectations.json`. Regenerate it deterministically with:

```sh
python3 scripts/make-fixtures.py fixtures/ExactMatching
```

For manual native acceptance, run Rupick, use **Open Project…** to select the fixture root, and use **Choose Images…** for the Incoming files. Renamed and hidden-colour images each yield two distinct Icon entries; the remaining valid inputs yield no matches, and broken.png shows an error. Inspect the incoming and candidate images side by side, select the 2x dark alternative, and verify it is labelled Alternative. Check that the incomplete-scan notice remains visible for the broken catalog, and that the exact-only limitation appears at the bottom.

For a larger project, use a renamed copy of a known catalog PNG or JPEG and a known new PNG or JPEG, keeping these copies outside the project. Compile and run the **same session implementation** through the local validation executable:

```sh
swiftc -swift-version 6 -parse-as-library \
  rupick/ProjectSession.swift rupick/CatalogComparison.swift rupick/ProjectIgnoreRules.swift \
  scripts/validate-project.swift -o /tmp/rupick-validate
/tmp/rupick-validate /path/to/project /path/to/duplicate.png /path/to/new.png
```

It also re-encodes the duplicate with different metadata and adds a corrupt input. It fails on a missed or changed duplicate result, a false exact match, an unreadable valid input, an unreported corrupt input, or a scan failure. Progress and main-actor heartbeats verify the session remains responsive. This executable is supplemental: the native UI test remains the primary acceptance path and exercises sandbox access through actual file panels.

To repeat native UI acceptance against another project, create `/tmp/rupick-acceptance.json` locally with keys `root`, `duplicate`, and `newImage`, each containing an absolute path. Optionally add `batchFolder`, a folder containing the duplicate, new PNG/JPEG inputs, and `broken.png` (invalid image bytes), to exercise multi-selection and failure isolation. Run `rupickUITests/testRealProjectWhenAcceptanceConfigIsProvided` through Xcode or `xcodebuild -only-testing:rupickUITests/rupickUITests/testRealProjectWhenAcceptanceConfigIsProvided`. Without that file the optional test is skipped. Remove it afterward. Never commit this config, project images, paths, screenshots, test bundles, or logs from confidential projects.

During a large search, navigate existing results, open the image panel, cancel it, and select another incoming image. Confirm progress continues, provisional matches appear, and variant controls remain usable. Compare checksums of catalog contents before and after validation to confirm the project is untouched.

The deployment target is macOS 15 on Apple silicon (arm64). Debug and arm64 Release builds validate the deployment target and SDK availability checks. Runtime validation is performed on macOS 26.7.1 with Xcode 27.0 on Apple silicon; a macOS 15 runtime is unavailable in the current environment. Testing on that minimum runtime remains a release validation item, not a claimed test result.

## Batch acceptance (#5)

Native UI fixtures exercise multiple selection of the Incoming folder and a Finder batch drop, then navigate from a corrupt image to a duplicate and a new image. They also generate a JPEG input locally. The corrupt image shows recovery guidance without a no-match status; valid comparisons continue. Skipped catalog entries retain an incomplete-scan summary, and zero candidates are labelled incomplete rather than No matches found. The session boundary also covers a missing project root, cancellation, obsolete work, duplicate input URLs, and independent per-image statuses.

Finder drops accept local PNG/JPEG file URLs, preserve the drop order, and add each URL only once. Open a project first; unsupported dropped files and provider failures show recovery guidance. The image picker and Finder drops share the same ingestion path.

All zero-match messaging describes the search result only. The visible exact-match limitation explicitly says that no matches does not guarantee an image is safe to import. A failed scan, cancelled search, skipped catalog files, and provisional comparison never use the completed No matches found state.

Validation for #5 passed on the local macOS environment: native multi-selection and Finder batch ingestion, PNG/JPEG (including `.jpe`) acceptance, list navigation, side-by-side matches, isolated corrupt input, retained skipped-catalog warnings, completed no-match messaging, and a project removed before comparison. A separate local-project session run found the known duplicate, preserved the metadata/re-encoded match, rejected the known new image, and isolated corruption while publishing progress and main-actor heartbeats. Native local-project batch navigation also passed. Catalog-file checksums were unchanged. Confidential acceptance inputs, configuration, and test artifacts remain outside the repository.

## Project ignore rules

Discovery applies `.gitignore` files from the selected root and its subdirectories, including ordered negation, nested overrides, anchored paths, directory patterns, and wildcard/globstar patterns. Ignored directories are pruned before discovery. Ignored metadata and image representations are excluded from catalog comparison. These intentional exclusions do not count as unreadable/skipped files. Explicit incoming images still compare even when their paths match an ignore rule. Git's internal `.git` directories are excluded.

Rules are evaluated locally inside the app sandbox; no Git executable is required. The selected folder defines the boundary: parent ignore files, global Git excludes, `.git/info/exclude`, and Git's tracked-file index are not consulted. A path matching the project-local rules is excluded even if it was previously committed. Native fixtures include ignored duplicate and corrupt catalogs; session coverage exercises nested overrides, anchoring, negation, escaped literals/spaces, ranges, and globstars.

Local-project ignore validation matched Git's reference result and reported zero skipped files. The known duplicate, differently encoded copy, known new image, and corrupt-input isolation checks passed with progress and main-actor heartbeats. Native acceptance checks the expected included count and absence of an incomplete-scan warning through local-only optional `expectedAssets` and `expectedSkipped` config values.

## Existing project duplicates (#16)

Opening a project automatically scans its existing PNG/JPEG representations without incoming images. Select a duplicate group in the sidebar. Each group contains distinct asset locations and lists every matching representation's filename, scale, idiom, and appearance metadata. The two Asset pickers independently select members for side-by-side inspection; each Representation picker exposes matches and alternatives. **Project Duplicates** returns to this view after incoming comparison.

Native synthetic tests cover a three-member group, a separate pair, same-named assets in different catalogs, alternatives, unique assets, ignored duplicate/corrupt catalogs, unreadable metadata, and a completed empty scan. Session tests cover exact normalized equality, transparent colour, dimensions/padding, self-match exclusion, repeated representations, incomplete scans, provisional groups, cancellation, and failure/reset. The existing incoming-image tests remain applicable.

The local validation executable now scans without incoming images first, verifies group uniqueness and distinct membership, and checks a group's complete membership against incoming comparison of its reference representation. The optional native acceptance configuration supports `expectedDuplicateGroups` alongside `expectedAssets` and `expectedSkipped`; positive group counts also require the native member and representation controls. Keep local-project configuration, inputs, content manifests, screenshots, and test logs outside the repository.
