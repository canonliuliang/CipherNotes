import AppKit
import SwiftUI

@main
struct CipherNotesApp: App {
    @StateObject private var store: VaultStore
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("noteSort") private var noteSortRawValue = NoteSort.updatedNewest.rawValue
    @AppStorage("noteFilter") private var noteFilterRawValue = NoteFilter.active.rawValue

    init() {
        if ProcessInfo.processInfo.environment["CIPHERNOTES_ALLOW_CAPTURE"] == "1" {
            let demoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CipherNotes-DeveloperDemo", isDirectory: true)
            try? FileManager.default.removeItem(at: demoDirectory)
            let demoVaultURL = demoDirectory.appendingPathComponent("vault.json")
            _store = StateObject(wrappedValue: VaultStore(vaultURL: demoVaultURL))
        } else {
            _store = StateObject(wrappedValue: VaultStore())
        }
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(appAppearance.colorScheme)
                .onAppear { applyAppKitAppearance(appAppearance) }
                .onChange(of: appAppearanceRawValue) { _, newValue in
                    applyAppKitAppearance(AppAppearance(rawValue: newValue) ?? .system)
                }
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") { post(.cipherNotesNewNote) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.state != .unlocked)
            }
            CommandMenu("笔记") {
                Button("新建笔记") { post(.cipherNotesNewNote) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.state != .unlocked)
                Button("复制为新笔记") { post(.cipherNotesDuplicateNote) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Button("置顶 / 取消置顶") { post(.cipherNotesTogglePinned) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Button("收藏 / 取消收藏") { post(.cipherNotesToggleFavorite) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Button("归档 / 移回") { post(.cipherNotesToggleArchived) }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                    .disabled(store.state != .unlocked)
                Button("复制笔记内容") { post(.cipherNotesCopyNote) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(store.state != .unlocked)
                Button("删除所选笔记") { post(.cipherNotesDeleteNote) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.state != .unlocked)
                Divider()
                Button("导出所选笔记为共享文件…") { post(.cipherNotesExportNote) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Button("导出所选笔记为 Markdown…") { post(.cipherNotesExportMarkdown) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Button("导出所选笔记为 TXT…") { post(.cipherNotesExportText) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Button("导入共享文件…") { post(.cipherNotesImportNote) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Divider()
                Picker("排序方式", selection: $noteSortRawValue) {
                    ForEach(NoteSort.allCases) { sort in
                        Text(sort.label).tag(sort.rawValue)
                    }
                }
                Picker("筛选范围", selection: $noteFilterRawValue) {
                    ForEach(NoteFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter.rawValue)
                    }
                }
            }
            CommandMenu("账号与安全") {
                Button("安全中心…") { post(.cipherNotesShowSecurityCenter) }
                    .disabled(store.state != .unlocked)
                Button("账户与安全…") { post(.cipherNotesShowUserManagement) }
                    .disabled(store.accounts.isEmpty)
                Button(store.currentAccountAdvancedDataProtectionEnabled ? "关闭当前账号高级数据保护" : "开启当前账号高级数据保护") {
                    store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
                }
                .disabled(store.state != .unlocked)
                Button("生成新的恢复码") { store.rotateRecoveryCode() }
                    .disabled(store.state != .unlocked)
                Text(store.state == .unlocked ? "当前账户：\(store.signedInUsername ?? "本地账户")" : "纯免费本地版本")
            }
            CommandMenu("保险库") {
                Button("立即锁定") { store.lock() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(store.state != .unlocked)
                Button("账户与安全…") { post(.cipherNotesShowUserManagement) }
                    .disabled(store.accounts.isEmpty)
                Button("移入照片或文件…") { post(.cipherNotesAddAttachments) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Divider()
                Button("备份保险库…") { post(.cipherNotesBackupVault) }
                Button("从备份还原…") { post(.cipherNotesRestoreVault) }
                Button("生成新的恢复码") { store.rotateRecoveryCode() }
                    .disabled(store.state != .unlocked)
            }
            CommandMenu("外观") {
                Picker("外观", selection: $appAppearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance.rawValue)
                    }
                }
            }
            CommandMenu("帮助") {
                Button("更新日志") { post(.cipherNotesShowChangelog) }
                Button("法律与隐私声明") { post(.cipherNotesShowLegalDisclosure) }
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private func applyAppKitAppearance(_ appearance: AppAppearance) {
        switch appearance {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
