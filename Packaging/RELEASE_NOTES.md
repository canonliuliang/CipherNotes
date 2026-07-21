# CipherNotes 1.1.5 - 主工作区恢复

## Summary

CipherNotes 1.1.5 restores the uncluttered post-login workspace after the account-entry redesign.

## Highlights

- Removes the global bottom utility strip after login so it no longer compresses the notes and vault workspace.
- Keeps Security Center visible as a dedicated native toolbar control.
- Leaves low-frequency account, appearance, changelog, and legal actions in the standard macOS menu bar.
- Preserves the fixed account selector and responsive login form panel introduced in 1.1.4.
- Adds a minimum-window regression test for the unlocked workspace.

## Downloads

- `密笺-1.1.5.pkg`: recommended public installer.
- `密笺-1.1.5.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 33 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.5` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
