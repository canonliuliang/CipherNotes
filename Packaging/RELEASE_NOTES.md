# CipherNotes 1.0.3 - GitHub 风格官网与发布流程

## Summary

CipherNotes 1.0.3 focuses on product polish and publishing clarity. The website now uses a GitHub-inspired repository layout, the release/download story is clearer, and all public-facing version references are aligned with the packaged release.

## What's Changed

- Rebuilt the website with a GitHub-style header, repository hero, Release card, README section, privacy matrix, development flow, and download panel.
- Replaced rough character/CSS icons with consistent inline SVG icons.
- Clarified that pushing source code updates the repository and Pages, but public downloads update only after a GitHub Release is created or updated with the new installer/archive assets.
- Synchronized README, website, GitHub Pages, local product introduction output, release metadata, Info.plist, and the in-app changelog to version 1.0.3.

## Downloads

- `密笺安装器.pkg`: recommended installer.
- `密笺-macOS.zip`: portable app archive.

## Verification Before Publishing

- `swift test --scratch-path /tmp/ciphernotes-test`
- `Packaging/build-release.sh`
- Confirm the GitHub Release assets include the new `pkg` and `zip`.

## Publishing Reminder

After pushing `main`, either push tag `v1.0.3` or run the GitHub `Release` workflow manually from the Actions tab. The workflow will build the app, create or update the Release, and upload the generated files.
