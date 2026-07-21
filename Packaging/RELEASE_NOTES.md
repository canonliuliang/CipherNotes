# CipherNotes 1.1.6 - 经典界面回归

## Summary

CipherNotes 1.1.6 restores the proven 1.0.8 interface throughout the app while retaining the current responsive login page and encrypted data model.

## Highlights

- Restores the 1.0.8 notes, vault, viewer, toolbar, settings, and security-center interface.
- Preserves the current login, registration, and recovery panel exactly, including its fixed selector and responsive height animation.
- Keeps the current encrypted vault format, equal-account model, security fixes, and local data compatibility.
- Adapts the restored interface to asynchronous image previews and the current import-job state model.
- Verifies both locked and unlocked minimum-window rendering.

## Downloads

- `密笺-1.1.6.pkg`: recommended public installer.
- `密笺-1.1.6.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 33 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.6` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
