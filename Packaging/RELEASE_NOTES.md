# CipherNotes 1.1.13 - 登录界面重构

## Summary

CipherNotes 1.1.13 rebuilds the login, registration, and recovery surface around a compact native macOS layout.

## Highlights

- Centers the authentication surface consistently in minimum-size and full-screen windows.
- Removes the application footer while locked, keeping account actions focused and uncluttered.
- Replaces the duplicated account summary and picker with one full-width native account menu.
- Makes the primary login, registration, and recovery actions use the complete form width.
- Keeps the three-mode selector stable while the glass content region animates to the required height.
- Prevents first-frame mode mismatch and form clipping during registration and login transitions.
- Adds dedicated locked-account and empty-vault visual regression snapshots.

## Downloads

- `密笺-1.1.13.pkg`: recommended public installer.
- `密笺-1.1.13.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 43 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.13` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
