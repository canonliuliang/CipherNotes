# CipherNotes 1.1.1 - 登录界面与窗口适配

## Summary

CipherNotes 1.1.1 refines the account entry experience so it remains calm, native, and fully reachable in compact macOS windows.

## Highlights

- Rebuilds the login, registration, and recovery entry layout around adaptive vertical space instead of a fixed-height form.
- Keeps account entry centered at normal window sizes and makes the full form safely scrollable at compact heights.
- Removes the empty fixed form area that made account-mode changes feel visually unstable.
- Consolidates bottom-window tools into native macOS menus, preserving every action without horizontal overflow.
- Retains the automated 860x620 light/dark/accent rendering check for the minimum supported window.

## Downloads

- `密笺-1.1.1.pkg`: recommended public installer.
- `密笺-1.1.1.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 32 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.1` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
