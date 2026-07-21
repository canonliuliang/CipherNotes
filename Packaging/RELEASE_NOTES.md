# CipherNotes 1.1.7 - 允许系统截屏

## Summary

CipherNotes 1.1.7 allows standard macOS screenshots, screen recording, and meeting-window sharing while preserving the restored 1.0.8 interface and current login page.

## Highlights

- Removes the system window-sharing exclusion that blocked screenshots and recordings.
- Allows macOS screenshots, screen recording, and meeting-window sharing of visible app content.
- Keeps Highest Protection focus shielding, auto-lock, and sensitive preview-cache clearing.
- Clarifies the screen-capture boundary in the legal and privacy disclosure.
- Preserves the restored 1.0.8 interface and current responsive login page.

## Downloads

- `密笺-1.1.7.pkg`: recommended public installer.
- `密笺-1.1.7.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 33 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.7` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
