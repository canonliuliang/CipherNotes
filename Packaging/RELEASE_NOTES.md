# CipherNotes 1.0.7 - macOS 原生界面与 Liquid Glass 收口

## Summary

CipherNotes is a privacy-first, fully local encrypted notes app and file vault for macOS. This 1.0.7 build refines the interface around native macOS hierarchy and uses Liquid Glass only where it supports navigation and controls.

## Highlights

- Native sidebar/list hierarchy and system toolbar background for the main workspace.
- Liquid Glass is limited to floating panels, status surfaces, and controls; reading and editing areas stay content-first.
- System accent colors, quieter shadows, fewer custom gradients, and improved dark-mode contrast.
- The isolated Developer screenshot mode and concise security-log behavior from 1.0.6 remain available.

## Previous release highlights

- Developer screenshot mode uses a temporary vault and a single `Developer` account; it cannot open the normal local vault or other accounts.
- The app shows a persistent `Developer Demo` warning while capture mode is active.
- Security logs retain the most recent 120 entries and collapse identical events repeated within five seconds.
- The security log view shows the most recent 40 filtered entries for a calmer interface.

## What's Changed

- Removed device biometric unlock from the app flow; CipherNotes now relies on account passwords and recovery codes.
- Made the decoy space persistent and separately encrypted, so decoy notes and vault files can be saved without touching real account data.
- Stabilized the login mode switcher height to avoid layout jumps between login, registration, and recovery.
- Changed Highest Protection buttons to use different visual treatment when enabling versus disabling the mode.
- Expanded the legal/privacy disclosure with clearer threat boundaries and limitations.
- Defined the version rule: user-visible feature/security changes require a new patch version; builds increment for packaging iterations.
- Added a main workspace status strip for current account, protection mode, auto-lock, and vault count.
- Reworked Account & Security to follow the clearer Security Center hierarchy: status cards, account section, password section, and danger zone.
- Turned Advanced Data Protection into a clearer mode card that lists the blocked copy/export/share/preview paths.
- Made decoy password setup calmer by keeping destructive erase mode behind an explicit reveal.
- Added a vault import queue with per-file progress for large encrypted imports.
- Fixed appearance switching by syncing SwiftUI and AppKit, so menus, alerts, and file panels follow the selected light/dark mode.
- Improved custom button contrast in both light and dark modes.
- Added editor save feedback with `正在保存` / `已保存` state and a manual save control.
- Added actionable empty states for notes, search results, and archive views.
- Added a Security Center version/update card with direct links to the latest GitHub Release and website.
- Made Security Center quick actions and backup controls adapt to narrow windows.
- Stabilized the Notes/Vault workspace switcher height so switching sections no longer makes the top control jump.
- Moved the workspace toolbar to the shared container so Notes and Vault keep the same chrome height.
- Kept the notes sidebar protection status visible in both standard and advanced modes to avoid header height changes.
- Made the Vault header and file-type filter adapt without sudden wrapping at common window widths.
- Added shared release validation for local packaging, CI, and GitHub Release publishing.
- Improved the README with a clearer product story, "Why Choose CipherNotes", release safety checks, and large-file vault positioning.
- Added an in-app manual update check that compares the current app version with GitHub Releases latest.
- Improved vault large-file imports with cancellation, remaining-time estimates, and clearable completed import records.
- Added no-temp-file internal vault viewers for images, text, and PDFs so protected files do not need to be opened in external apps.
- Added an in-memory audio vault player for common audio files, with no temporary plaintext export and no external player launch.
- Added a Highest Protection privacy shield that covers the app and clears preview caches when the window leaves the active state.
- Kept video files inside the vault instead of opening external apps; no-temp-file video playback is reserved for a future hardened player.
- Reframed Advanced Data Protection as a stricter Highest Protection mode in the security UI.
- Added attachment-directory Spotlight prevention with `.metadata_never_index` and lock-time preview cache cleanup.
- Improved the Account & Security danger zone with separate confirmation guidance for deleting the current account and erasing all CipherNotes data.
- Disabled destructive buttons until the current password is entered and the exact confirmation text matches the selected action.
- Made Security Center and Account & Security sheets more adaptable, reducing cramped layouts and inaccessible content.
- Kept release metadata, README, website, GitHub Pages, packaging configuration, and the in-app changelog aligned to version 1.0.7.
- Preserved the GitHub-inspired product website and automated Release workflow from 1.0.3.

## Downloads

- `密笺-<version>-普通版.pkg`: recommended public installer.
- `密笺-<version>-普通版.zip`: public portable app archive.
- `密笺-Developer-<version>.pkg`: isolated Developer build for screenshots and testing.
- `密笺-Developer-<version>.zip`: isolated Developer portable archive.

## Verification Before Publishing

- `swift test --scratch-path /tmp/ciphernotes-test`
- `Packaging/build-release.sh`
- Confirm the GitHub Release assets include the new `pkg` and `zip`.

## Publishing Reminder

After pushing `main`, either push tag `v1.0.7` or run the GitHub `Release` workflow manually from the Actions tab. The workflow will build the app, create or update the Release, and upload the generated files.
