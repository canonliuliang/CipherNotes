# CipherNotes 1.1.14 - 界面入口与状态安全整理

## Summary

CipherNotes 1.1.14 consolidates repeated controls into a clearer native macOS hierarchy and closes two locked-state settings paths found during review.

## Highlights

- Keeps the main toolbar focused on Security Center, app settings, and immediate lock.
- Removes the duplicate bottom shortcut bar and repeated contextual commands without removing capabilities.
- Makes Security Center the single place for Highest Protection and recovery-code management.
- Keeps vault import in the vault header, and note actions in note menus and item context menus.
- Stabilizes the notes/vault segmented control at a fixed width and height.
- Removes repeated account/protection status from the notes sidebar and duplicate empty-state creation actions.
- Blocks account settings while locked and dismisses sensitive settings sheets when the vault locks automatically.
- Preserves the encrypted media viewer, super-private space, decoy space, local security log, backups, changelog, legal disclosure, and equal local-account model.

## Downloads

- `密笺-1.1.14.pkg`: recommended public installer.
- `密笺-1.1.14.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 43 automated tests
- Minimum-window light/dark/accent render checks
- Locked, registration, and unlocked-workspace visual regression snapshots
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.14` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
