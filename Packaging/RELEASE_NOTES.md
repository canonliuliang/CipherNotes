# CipherNotes 1.1.4 - 灵动登录面板

## Summary

CipherNotes 1.1.4 restores the intended account-entry interaction: a stable segmented selector above a glass panel that smoothly resizes around each form.

## Highlights

- Keeps the login, registration, and recovery segmented selector at a fixed position and height.
- Animates the glass panel to each form's measured content height with a restrained spring response.
- Fades and gently offsets form content during mode changes while respecting Reduce Motion.
- Anchors the account panel at the top so expansion happens downward without shifting the selector.
- Restores Appearance, Security Center, Accounts, Changelog, and Legal as direct bottom-window controls.

## Downloads

- `密笺-1.1.4.pkg`: recommended public installer.
- `密笺-1.1.4.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 32 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.4` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
