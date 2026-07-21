# CipherNotes 1.1.2 - 登录稳定性与安全入口

## Summary

CipherNotes 1.1.2 fixes an account-entry rendering regression and restores the security center as the primary bottom-window action.

## Highlights

- Removes the account-entry geometry dependency that could leave a restored app window blank.
- Uses one reliable native scrolling surface for login, registration, and recovery, so every field remains reachable at any window height.
- Restores Security Center as the visible primary control; appearance and secondary utilities now live under More.
- Retains overflow-proof menus, compact-window behavior, and automated 860x620 light/dark/accent rendering checks.

## Downloads

- `密笺-1.1.2.pkg`: recommended public installer.
- `密笺-1.1.2.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 32 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.2` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
