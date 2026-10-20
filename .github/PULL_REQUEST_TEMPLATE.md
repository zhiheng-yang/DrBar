## What and why

<!-- What does this change, and why? Link the issue if there is one. -->

## Checks

- [ ] `swift test --package-path Packages/DrBarKit` and the lint pass
- [ ] The app builds and the change works in the app
- [ ] Screenshots in light and dark mode for visible changes
- [ ] New UI text is in the string catalogs (`scripts/sync-strings.sh`), with translations
- [ ] A line under "Unreleased" in `CHANGELOG.md` for anything users notice
- [ ] `docs/SPEC.md` updated for changed behavior
- [ ] `user.json` from earlier releases still opens, if the data format changed
