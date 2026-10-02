# Exact-match acceptance

The agreed seams are the observable `ProjectSession` and the running native macOS app, as specified in #3 and implemented for #4. No matching-helper or cache-layout tests are used.

`fixtures/ExactMatching` is a synthetic project with two catalogs sharing the name Icon, light and dark scale variants, a corrupt catalog, and incoming images covering renamed/re-encoded content, transparent hidden colour, a new visible colour, dimensions, padding, partial alpha, and corruption. Expected results are in `expectations.json`. Regenerate it deterministically with:

```sh
python3 scripts/make-fixtures.py fixtures/ExactMatching
```

For manual native acceptance, run Rupick, use **Open Project…** to select the fixture root, and use **Choose Images…** for the Incoming files. Renamed and hidden-colour images each yield two distinct Icon entries; the remaining valid inputs yield no matches, and broken.png shows an error. Inspect the incoming and candidate images side by side, select the 2x dark alternative, and verify it is labelled Alternative. Check that the incomplete-scan notice remains visible for the broken catalog, and that the exact-only limitation appears at the bottom.

For a larger project, use a renamed copy of a known catalog PNG or JPEG and a known new PNG or JPEG, keeping these copies outside the project. Compile and run the **same session implementation** through the local validation executable:

```sh
swiftc -swift-version 6 -parse-as-library \
  rupick/ProjectSession.swift rupick/CatalogComparison.swift \
  scripts/validate-project.swift -o /tmp/rupick-validate
/tmp/rupick-validate /path/to/project /path/to/duplicate.png /path/to/new.png
```

It also re-encodes the duplicate with different metadata and adds a corrupt input. It fails on a missed or changed duplicate result, a false exact match, an unreadable valid input, an unreported corrupt input, or a scan failure. Progress and main-actor heartbeats verify the session remains responsive. This executable is supplemental: the native UI test remains the primary acceptance path and exercises sandbox access through actual file panels.

To repeat native UI acceptance against another project, create `/tmp/rupick-acceptance.json` locally with keys `root`, `duplicate`, and `newImage`, each containing an absolute path. Run `rupickUITests/testRealProjectWhenAcceptanceConfigIsProvided` through Xcode or `xcodebuild -only-testing:rupickUITests/rupickUITests/testRealProjectWhenAcceptanceConfigIsProvided`. Without that file the optional test is skipped. Remove it afterward. Never commit this config, project images, paths, screenshots, test bundles, or logs from confidential projects.

During a large search, navigate existing results, open the image panel, cancel it, and select another incoming image. Confirm progress continues, provisional matches appear, and variant controls remain usable. Compare checksums of catalog contents before and after validation to confirm the project is untouched.

The deployment target is macOS 15. Debug and universal arm64/x86_64 Release builds validate the deployment target and SDK availability checks. Runtime validation is performed on macOS 26.7.1 with Xcode 27.0 on Apple silicon; a macOS 15 runtime and an Intel machine are unavailable in the current environment. These older-runtime and physical Intel checks remain a release validation item, not a claimed test result.
