# CipherNotes 1.1.0 - 内置媒体与大文件体验

## Summary

CipherNotes 1.1.0 rebuilds the encrypted file-vault viewer and completes a broad performance, storage-integrity, accessibility, and release-tooling pass.

## Highlights

- Views images, PDF files, text, audio, and video inside CipherNotes.
- Streams audio and video from encrypted 4 MB chunks without plaintext temporary files or external applications.
- Downsamples thumbnails off the main thread and bounds preview memory with LRU eviction.
- Adds pause, resume, progress, cancellation, and background deletion behavior for large vault files.
- Debounces note search and reuses an incremental normalized search index.
- Keeps note autosave coalesced and skips unchanged encrypted writes.
- Keeps a validated recovery copy beside `vault.json` and restores it if the primary metadata file is damaged.
- Adds a SHA-256 manifest to new backups and validates it before restore.
- Stores versioned password-derivation settings per account for future KDF upgrades.
- Retains progressive login throttling and adds encrypted security-audit export.
- Improves VoiceOver labels and keyboard-accessible media controls.
- Adds automated 860x620 rendering checks across light, dark, blue-accent, and mint-accent combinations.
- Updates official GitHub Actions to current runtimes, removing the Node.js 20 deprecation path.

## Downloads

- `密笺-1.1.0.pkg`: recommended public installer.
- `密笺-1.1.0.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 32 automated tests
- Minimum-window light/dark/accent render checks
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.0` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
