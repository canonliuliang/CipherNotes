# CipherNotes 1.0.9 - 安全加固与性能优化

## Summary

CipherNotes 1.0.9 improves encrypted-save responsiveness and hardens authentication, recovery, shared-note import, deletion, backup restore, and vault-file handling.

## Highlights

- Batches note title, body, and tag changes into one encrypted persistence transaction.
- Skips no-op note saves instead of repeating JSON encoding, AES-GCM encryption, and atomic disk writes.
- Encrypts vault files of 4 MB or larger on a background utility task to keep the interface responsive.
- Adds escalating login backoff after repeated failed authentication attempts.
- Requires non-empty shared-note passwords and enforces attachment count and size limits.
- Validates encrypted attachment chunk sizes and declared plaintext lengths before accepting data.
- Generates a new recovery code after an account password change, invalidating the previous recovery code.
- Cancels active vault imports when locking and prevents backup while imports are active.
- Makes attachment, account, and local-data deletion fail safely when filesystem removal cannot be confirmed.
- Requires an unlocked account, current password, and explicit confirmation before restoring a backup.

## Downloads

- `密笺-1.0.9.pkg`: recommended public installer.
- `密笺-1.0.9.zip`: portable app archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift release build
- 29 automated tests
- Strict application code-signature verification
- Installer payload verification

## Publishing Reminder

Push tag `v1.0.9` after the release commit. The GitHub Release workflow builds the app, creates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
