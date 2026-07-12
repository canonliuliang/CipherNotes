# CipherNotes 1.0.4 - 危险操作确认与窗口适配

## Summary

CipherNotes is a privacy-first, fully local encrypted notes app and file vault for macOS. Version 1.0.4 sharpens the product feel around destructive actions and window ergonomics so the app reads less like a utility build and more like a finished product.

## What's Changed

- Improved the Account & Security danger zone with separate confirmation guidance for deleting the current account and erasing all CipherNotes data.
- Disabled destructive buttons until the current password is entered and the exact confirmation text matches the selected action.
- Made Security Center and Account & Security sheets more adaptable, reducing cramped layouts and inaccessible content.
- Kept release metadata, README, website, GitHub Pages, packaging configuration, and the in-app changelog aligned to version 1.0.4.
- Preserved the GitHub-inspired product website and automated Release workflow from 1.0.3.

## Downloads

- `密笺安装器.pkg`: recommended installer.
- `密笺-macOS.zip`: portable app archive.

## Verification Before Publishing

- `swift test --scratch-path /tmp/ciphernotes-test`
- `Packaging/build-release.sh`
- Confirm the GitHub Release assets include the new `pkg` and `zip`.

## Publishing Reminder

After pushing `main`, either push tag `v1.0.4` or run the GitHub `Release` workflow manually from the Actions tab. The workflow will build the app, create or update the Release, and upload the generated files.
