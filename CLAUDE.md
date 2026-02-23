# CLAUDE.md

## Release Process

- Release is triggered by pushing a git tag: `git tag v0.x.x && git push origin v0.x.x`
- CI (CircleCI) builds, signs, and uploads the DMG + metadata to R2
- **IMPORTANT: Always update `CHANGELOG.md` before tagging a release.** Add an entry under `## [vX.Y.Z] - YYYY-MM-DD` with the changes for this version. The CI pipeline uploads CHANGELOG.md to R2, and the website reads it from there. Missing changelog entries mean the release won't appear on https://www.airtype.space/changelog.
