# CipherNotes / 密笺

A privacy-first, fully local encrypted notes app for macOS.

CipherNotes is built for private notes, photos, documents, archives, and other files you want to keep on your Mac instead of in a cloud account. It has no sync server, no analytics, no ads, no subscription, and no paid feature gate.

[Website](https://canonliuliang.github.io/CipherNotes/) · [Download latest release](https://github.com/canonliuliang/CipherNotes/releases/latest) · [Report an issue](https://github.com/canonliuliang/CipherNotes/issues)

![CI](https://github.com/canonliuliang/CipherNotes/actions/workflows/ci.yml/badge.svg)

![CipherNotes main window](docs/media/app-screenshot.png)

## Download

Get the latest version from [GitHub Releases](https://github.com/canonliuliang/CipherNotes/releases/latest).

- Current release: `1.0.4` · 危险操作确认与窗口适配.
- `密笺安装器.pkg`: recommended installer.
- `密笺-macOS.zip`: portable archive.

Requires macOS 14 or later.

## Highlights

- Fully local encrypted notes and file vault for macOS.
- AES-256-GCM encryption for note payloads and vault files.
- Equal local accounts: no administrator account, no universal password, no hidden superuser.
- File vault for photos, PDFs, archives, scans, and large offline files.
- Chunked vault storage: large files are encrypted in 4 MB chunks, imported in the background, and exported by streaming.
- Touch ID convenience unlock per account, with password fallback.
- Recovery codes for account password reset.
- Local encrypted security log for sensitive events.
- Advanced Data Protection mode that tightens auto-lock and blocks copying, exporting, sharing, previews, and sensitive filename exposure.
- Decoy password option for Advanced Data Protection: open a temporary fake space or erase local data when the configured decoy password is entered.
- Local backup and restore.
- Free: no membership, purchase flow, restore purchase, or paid switch.

## Screenshots And Website

- Product website: [canonliuliang.github.io/CipherNotes](https://canonliuliang.github.io/CipherNotes/)
- Screenshots live in [docs/media](docs/media).
- Download buttons on the website point to [Releases latest](https://github.com/canonliuliang/CipherNotes/releases/latest).

## Privacy Boundary

CipherNotes does not upload notes, files, account data, usage events, recovery codes, or passwords. There is no remote account and no cloud recovery.

What is stored locally:

- Account display names, so the login screen can show local accounts.
- Salted username hashes for local username matching.
- Encrypted note payloads.
- Encrypted vault file chunks.
- Encrypted local security logs.

What is not stored in plaintext:

- Note titles and bodies.
- Vault file contents.
- Account passwords.
- Recovery codes.
- Shared-note passwords.
- Sensitive security-log object names such as note titles, file names, or note bodies.

If you forget an account password and lose its recovery code, that account's encrypted content cannot be recovered. Other accounts are not master keys.

## Data Location

Default vault file:

```text
~/Library/Application Support/CipherNotes/vault.json
```

Encrypted vault file chunks:

```text
~/Library/Application Support/CipherNotes/Attachments/
```

## Develop

Requires macOS 14 or later and a Swift 6 capable Xcode toolchain.

```sh
swift run --scratch-path /tmp/ciphernotes-run CipherNotes
```

You can also open `Package.swift` in Xcode and run the `CipherNotes` scheme.

## Test

```sh
swift test --scratch-path /tmp/ciphernotes-test
```

## Package

Release metadata is centralized in `Packaging/release.env`. Before publishing a new download, update that file, then run:

```sh
Packaging/build-release.sh
```

The script runs tests, builds the release app, and updates:

- `outputs/密笺安装器.pkg`
- `outputs/密笺-macOS.zip`
- `outputs/使用说明.md`
- `outputs/产品介绍.html`
- `outputs/密笺图标.png`

The repository avoids keeping an expanded `.app` bundle in `outputs` to reduce Spotlight and Git noise. Unzip the release archive when you need the app bundle.

Pushing source code to GitHub updates the repository and GitHub Pages, but it does not update what users download from the website by itself. The website download button points to GitHub Releases latest.

To publish a new public download:

```sh
git push origin main
git tag v1.0.4
git push origin v1.0.4
```

If you are using GitHub Desktop and do not want to push tags from Terminal, push `main`, open the repository's Actions tab, choose the `Release` workflow, and run it manually. Leave the tag field empty to use `Packaging/release.env`.

The `Release` workflow validates the version, runs the package script, creates or updates the GitHub Release, and uploads the generated `pkg`, `zip`, release notes, usage guide, website output, and icon.

## Upgrade From Older Vaults

Older vaults can be upgraded from the migration screen. Enter the old username and old master password; the old password becomes the new local account password, and existing notes are preserved. If you do not need the old data, you can discard the old vault and start fresh.

## Changelog

### 1.0.4 - 危险操作确认与窗口适配

- Added a main workspace status strip for current account, protection mode, auto-lock, and vault count.
- Reworked Account & Security to follow the clearer Security Center hierarchy: status cards, account section, password section, and danger zone.
- Turned Advanced Data Protection into a clearer mode card that lists the blocked copy/export/share/preview paths.
- Made decoy password setup calmer by keeping destructive erase mode behind an explicit reveal.
- Added a vault import queue with per-file progress for large encrypted imports.
- Improved the Account & Security danger zone: delete-account and erase-all-data now show separate confirmation requirements.
- Disabled destructive buttons until the current password is entered and the exact confirmation text matches the selected action.
- Changed Security Center and Account & Security sheets to use more flexible window sizing.
- Kept release metadata, README, website, GitHub Pages, packaging, and in-app changelog aligned.

### 1.0.3 - GitHub 风格官网与发布流程

- Rebuilt the product website with a GitHub-inspired repository layout, release card, README section, privacy matrix, and cleaner SVG icon system.
- Added clearer release guidance: source pushes do not update public downloads until a GitHub Release is created or updated with new assets.
- Synchronized website, GitHub Pages, and local product introduction output.
- Started tightening account/password UX with clearer release naming and safer version consistency.

### 1.0.2 - 虚假密码与清晰按钮

- Added Advanced Data Protection decoy password actions for fake-space entry or local data destruction.
- Added a non-persistent decoy space that does not read or write the real vault.
- Improved button contrast for the bottom toolbar, vault cards, account rows, Security Center sections, and security log rows.
- Updated the in-app changelog so recent security changes are visible inside the app.

### 1.0.1 - 本地安全日志与高级保护收口

- Added encrypted local security logs in Security Center.
- Blocked copy, plain export, shared import/export, vault preview, vault export, and sensitive filename copying when Advanced Data Protection is enabled.
- Removed external password-manager helper prompts.
- Reworked README and website download links around GitHub Releases latest.

### 1.0.0

- Removed membership, purchases, restore purchase, and all paid feature gates.
- Removed the administrator model. All accounts are equal local accounts.
- Removed external password-manager helper prompts.
- Added local encrypted security logs in Security Center.
- Added Advanced Data Protection blocking for copy, export, sharing, vault preview, vault export, and sensitive filename copying.
- Added Advanced Data Protection decoy password actions for fake-space entry or local data destruction.
- Added stricter Touch ID fallback messaging without raw keychain error codes.
- Added chunked encrypted vault storage for large files.
- Added backup and restore authorization with current account password and fixed confirmation text.
- Added first-run intro, in-app changelog, legal/privacy disclosure, and release packaging flow.

### 0.10.0

- Converted account setup to local account creation.
- Added account recovery codes.
- Added account and safety management.
- Added local backup and restore.

### 0.9.x

- Added Advanced Data Protection account setting.
- Added pinned, favorite, archived notes, tags, Markdown preview, and note export.
- Added vault filtering, total size, filename copying, and large-file work.

### 0.8.x

- Improved Touch ID upgrade behavior.
- Reduced repeated keychain prompts.
- Added motion preferences and calmer UI transitions.

### 0.7.x

- Added encrypted file vault.
- Moved files out of note payloads into independent encrypted vault storage.
- Added import-then-delete workflow for source files.

### 0.3.0 - 0.6.x

- Added multi-account login.
- Added recovery codes, legal/privacy disclosure, encrypted shared-note import/export, Touch ID, changelog, appearance settings, sorting, duplication, editor stats, and autosave improvements.

## License

MIT License. See [LICENSE](LICENSE).
