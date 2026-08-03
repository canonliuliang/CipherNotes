# CipherNotes 1.1.15 - 安全持久化与原生交互重构

## Summary

CipherNotes 1.1.15 strengthens interrupted-write recovery, refines the encrypted file viewer, and gives the macOS workspace a clearer native hierarchy with consistent motion.

## Highlights

- Adds transaction-journal recovery for interrupted vault writes and restores.
- Restores encrypted metadata and attachments as one validated transaction.
- Splits authentication, security, persistence, backup, import, cache, and shared UI into focused modules.
- Improves the encrypted viewer with full-screen adaptation, native anchored zoom, 1:1 viewing, and cancellable neighboring preload.
- Keeps large vault-file imports chunked and off the main interface.
- Separates the workspace into a stable navigation band, quick overview panel, and content region.
- Adds consistent account, workspace, protection-state, list, empty-state, and viewer transitions.
- Removes the automatic sidebar toolbar item that caused the window title to shift between workspaces.
- Limits the in-app changelog to the latest 10 versions while retaining older history in the source.
- Respects the macOS Reduce Motion setting throughout the new transitions.
- Adds a documented local threat model and expanded persistence regression coverage.
- Unifies security, account, logs, backup, appearance, and update controls in one native settings window.
- Replaces routine success alerts with non-blocking in-app feedback.
- Adds an 8-second undo window for note deletion while keeping encrypted file deletion explicitly irreversible.
- Restores the previous standard auto-lock interval after Highest Protection is disabled.
- Improves encrypted viewer continuity with cached thumbnails and a clearer secure-loading state.

## Downloads

- `密笺-1.1.15.pkg`: recommended public installer.
- `密笺-1.1.15.zip`: portable application archive.

Requires macOS 14 or later.

## Verification

- Release metadata validation
- Swift debug and release builds
- 52 automated tests
- Interrupted-write and interrupted-restore recovery tests
- Metadata and attachment restore transaction test
- Minimum-window light/dark render checks
- Login, registration, workspace, and encrypted-viewer visual snapshots
- Strict application code-signature verification
- Installer payload verification

## Publishing

Push tag `v1.1.15` after the release commit. The GitHub Release workflow builds the same single formal application, creates or updates the Release, and uploads the installer, archive, release notes, user guide, product page, and icon.
