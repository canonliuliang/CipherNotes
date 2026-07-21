# CipherNotes 1.1.3 - 登录页渲染修复

## Summary

CipherNotes 1.1.3 removes the login scroll-container rendering path that could result in a blank application window on launch.

## Highlights

- Removes the account-entry scroll-container rendering path responsible for the blank launch regression.
- Uses the stable macOS window layout path for login, registration, and recovery while keeping the compact 860x620 form fully visible.
- Keeps Security Center as the visible primary control; Appearance remains grouped under More.
- Adds a render-content assertion so automated UI checks fail when the direct login screen contains only the background.

## Downloads

- `密笺-1.1.3.pkg`: recommended public installer.
- `密笺-1.1.3.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 32 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.3` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
