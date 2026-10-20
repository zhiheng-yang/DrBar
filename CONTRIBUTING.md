# Contributing

Thanks for helping. Bug reports, fixes and translations are all welcome.

**A deadline is wrong?** DrBar shows ccfddl's data as it is, so please report it to
[ccfddl](https://github.com/ccfddl/ccf-deadlines/issues). Once it is fixed there, DrBar picks it up
within 12 hours.

## Setup

Requirements: a Mac that runs Xcode 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The
app itself runs on macOS 14 and later.

```sh
scripts/bootstrap.sh
open DrBar.xcodeproj
```

`bootstrap.sh` installs XcodeGen with Homebrew if it is missing, copies
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and generates `DrBar.xcodeproj`. Set
your own bundle ID prefix in `Config/Local.xcconfig`; an Apple team is optional (see the file).
The generated project and `Local.xcconfig` are not committed; change `project.yml` instead of the
project file.

## Layout

| Path | What is there |
| --- | --- |
| `Packages/DrBarKit` | A Swift package. `DrBarKit`: models, planning, storage (Foundation only). `CCFDDLKit`: download and YAML parsing. `DrBarUI`: the bars, rows and axis. |
| `App` | The menu bar app: state (`AppStore`), the popover, the planner, settings, reminders, Mail. |
| `docs` | The design spec, an architecture overview, the user guide and the website (`index.html`, with its films in `media`, which GitHub Pages can serve from this folder). |

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit together.

## Seeing your changes

- **In Xcode:** the views have previews on sample data; open a view's file and show the canvas
  (⌥⌘↩) to see it update as you type. Run the app with ⌘R. To run it on sample data or in Chinese,
  tick `-DrBarDemo YES` or `-AppleLanguages (zh-Hans)` in Product › Scheme › Edit Scheme › Run ›
  Arguments.
- **From the terminal or another editor:** `scripts/run.sh` builds the debug app, puts it in
  `~/Applications` and opens it from there, with its log in the terminal; Ctrl-C quits it. Siri,
  Spotlight and Shortcuts only know an app that is opened from Applications, so this is the copy
  to try them with. Add `--demo` for sample data (your own data is not touched) and `--zh` for
  Chinese.
- **Every screen at once:** `scripts/run.sh --demo --snapshots` renders the main views in light and
  dark mode to `.build/snapshots`. Look at them before and after a visual change. It also runs
  Siri's actions on the sample data and writes what each answered, and whether it did what it said,
  to `intents.txt`.

## Commands

```sh
swift test --package-path Packages/DrBarKit        # unit tests, fast
scripts/run.sh [--demo] [--zh] [--snapshots]         # build and run, see above
xcodegen generate                                    # after editing project.yml
xcrun swift-format lint --recursive --strict App Packages/DrBarKit/Sources Packages/DrBarKit/Tests
xcrun swift-format format --in-place --recursive App Packages/DrBarKit/Sources Packages/DrBarKit/Tests
scripts/update-snapshot.sh                           # refresh the bundled ccfddl snapshot
scripts/sync-strings.sh                              # add new UI strings to the string catalogs
swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset   # redraw the app icon
```

## Guidelines

- Keep the app small: native Swift and SwiftUI, and Yams as the only dependency.
- Nothing leaves the Mac except the ccfddl download, and nothing is sent without the user's click.
- Never show a predicted or last year's date as a deadline.
- `user.json` from every release must keep decoding. New fields need defaults, and each release adds
  a fixture to `Packages/DrBarKit/Tests/DrBarKitTests/Fixtures`.
- Use system colors, SF Symbols and system controls. The bars are the one custom element.
- Don't rely on color alone: urgency and progress also show as length, shape or text.
- A change to behavior updates `docs/SPEC.md` in the same pull request.

## Translations

UI strings live in String Catalogs (`Localizable.xcstrings`) in `App/Resources` and
`Packages/DrBarKit/Sources/DrBarUI/Resources`, and Siri's phrases in
`App/Resources/AppShortcuts.xcstrings`. After adding UI text or a phrase, run
`scripts/sync-strings.sh`, then add translations in Xcode's catalog editor. The email to the
supervisor has its own small table, `MailStrings` in `ProgressSummary.swift`, because its language
is a setting.

To add a language, add it to both `Localizable.xcstrings` files, to `AppShortcuts.xcstrings` and
to `App/Resources/InfoPlist.xcstrings` in the catalog editor, and to `CFBundleLocalizations` in
`App/Info.plist`. Offering it for the email as well means a new `MailLanguage` case and its column
in `MailStrings`.

## Pull requests

Keep them focused, describe what changed and why, and make sure the tests and the lint pass.
UI changes are easier to review with a screenshot in light and dark mode.

## Releasing

For maintainers. Once, before the first release:

- Set `BUNDLE_ID_PREFIX` in `Config/Base.xcconfig` to the project's own prefix and commit it. It can
  never change afterwards, because users' data, notification permission and login item belong to
  the bundle ID; `scripts/release.sh` builds with that prefix, whatever `Config/Local.xcconfig`
  says, and refuses the placeholder.
- In the repository settings, turn on private vulnerability reporting, which `SECURITY.md` links
  to; allow GitHub Actions to create pull requests, for the weekly snapshot refresh; and publish
  GitHub Pages from the `docs` folder of `main`, for the website.

For each release:

1. Set `MARKETING_VERSION` and raise `CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig`.
2. Run `scripts/sync-strings.sh` and check in the catalog editor that every string is translated.
3. If the interface changed, render `scripts/run.sh --snapshots` and update the images in
   `docs/images`.
4. In `CHANGELOG.md`, move the entries under "Unreleased" to `## [<version>] - <date>` and add its
   link at the bottom, `[<version>]: https://github.com/zhiheng-yang/DrBar/releases/tag/v<version>`.
5. Add `user-v<version>.json` to `Packages/DrBarKit/Tests/DrBarKitTests/Fixtures`, saved by the new
   version, with a test that decodes it, so later releases keep reading it.
6. Send one progress email with Mail and one with another mail app: this is the one path the tests
   cannot cover.
7. Commit, then run `scripts/release.sh` on the clean tree. It writes `dist/DrBar-<version>.zip`,
   the app signed to run locally. With a team of the paid Apple Developer Program,
   `DEVELOPER_ID=1 scripts/release.sh` signs it with Developer ID and notarizes it instead; the
   script's header has the one-time setup.
8. Upload the zip to a draft release, download it, and open it as a user would (README › Get
   started), to check the first open.
9. Tag that commit `v<version>`, push the tag, and publish the release with the zip, the changelog
   entry and, while releases are signed to run locally, how to open DrBar the first time.
