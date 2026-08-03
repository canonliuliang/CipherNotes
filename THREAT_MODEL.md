# CipherNotes Threat Model

This document describes the security goals and limits of CipherNotes. It is a design contract, not a claim of forensic immunity.

## Assets

CipherNotes protects:

- note titles, bodies, organization metadata, and encrypted local security logs;
- files imported into the vault, including photos, documents, audio, and video;
- per-account vault keys, recovery wrapping material, decoy-space data, and super-private-space data;
- filenames and object names while Highest Protection is enabled.

Account display names remain visible in `vault.json` so users can choose a local account before unlocking. File sizes, encrypted-file counts, update timestamps, and the existence of a CipherNotes vault may also be observable.

## Cryptographic Design

- Note payloads and vault-file chunks use AES-256-GCM authenticated encryption.
- Each local account has its own random vault key.
- Account passwords derive wrapping keys with PBKDF2-HMAC-SHA256, a per-account salt, and the iteration count stored with that account.
- Recovery codes wrap the same random vault key through separate recovery material.
- Large files are encrypted independently in 4 MiB chunks. The viewer decrypts only requested chunks and does not create a plaintext temporary media file.
- Vault metadata writes use a transaction journal, a validated pending file, and a previous valid copy. Whole-vault restore stages and validates metadata and attachments before switching them into place.

## Threats Addressed

CipherNotes is designed to reduce exposure when:

- another person opens the app but does not know the account password;
- an attacker copies `vault.json` or encrypted attachment files from a powered-off or locked Mac;
- a file is too large to decrypt safely into memory in one operation;
- the app or Mac stops during a metadata save, attachment import, or backup restore;
- users want to view common photos, PDFs, text, audio, or video without handing plaintext to another application;
- an account needs a separately encrypted decoy or super-private workspace.

Protection against offline password guessing still depends heavily on password strength. A long, unique passphrase is essential.

## Threats Not Fully Addressed

CipherNotes cannot guarantee secrecy against:

- malware, a debugger, kernel extensions, or an administrator/root process running while the account is unlocked;
- keyloggers, accessibility capture, screen recording, screenshots, cameras, or meeting-sharing software;
- forensic acquisition of live memory, swap, sleep images, GPU surfaces, or operating-system caches;
- malicious replacement of the unsigned application or installer;
- weak, reused, observed, or coerced passwords and recovery codes;
- physical SSD recovery after deletion. Modern copy-on-write storage and wear levelling make verified per-file secure erasure unavailable to normal applications;
- a compromised macOS installation, firmware, dependency toolchain, or release pipeline;
- denial of service, deletion, corruption, or ransomware. Encryption does not replace offline backups.

Highest Protection reduces application-controlled exposure by tightening auto-lock, clearing preview caches, obscuring names, and blocking export/copy/share paths. It is not an anti-forensics mode and does not make visible content impossible to capture.

## Data Lifecycle

- Plaintext is created in memory only while an account is unlocked or content is actively processed.
- Locking clears in-memory workspace collections, cancels preview tasks, removes cached images, and overwrites the store's current key buffer on a best-effort basis.
- Swift, AppKit, AVFoundation, the allocator, and the operating system may retain copies outside the app's direct control. CipherNotes therefore does not claim guaranteed zeroization.
- Encrypted attachments are committed from uniquely named partial files. Incomplete or orphaned blobs are removed during startup cleanup.
- Security logs are encrypted inside the current account payload and can be disabled. They never intentionally include note text, passwords, recovery codes, or filenames.

## Recommended Operating Conditions

- Enable macOS FileVault and use a strong system login password.
- Fully shut down the Mac before it leaves your control when facing a serious physical-access threat.
- Use a long, unique CipherNotes passphrase and store the recovery code separately.
- Keep verified offline backups and test restoration periodically.
- Install only releases obtained from the official repository. Until Developer ID signing and notarization are added, verify release hashes and treat macOS warnings seriously.
- Avoid unlocking on a Mac you suspect is monitored or compromised.

## Security Regression Requirements

Changes to encryption, account authorization, restore, imports, viewers, or lock behavior must include regression tests. Release builds must pass the full Swift test suite and metadata validation before publication.
