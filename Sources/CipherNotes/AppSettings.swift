import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview, highestProtection, account, securityLogs, backup, appearance, updateAbout
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "概览"
        case .highestProtection: "最高保护"
        case .account: "账户"
        case .securityLogs: "安全日志"
        case .backup: "备份"
        case .appearance: "外观"
        case .updateAbout: "更新与关于"
        }
    }
    var systemImage: String {
        switch self {
        case .overview: "gearshape"
        case .highestProtection: "shield.lefthalf.filled"
        case .account: "person.crop.circle"
        case .securityLogs: "list.bullet.rectangle.portrait"
        case .backup: "externaldrive.badge.timemachine"
        case .appearance: "circle.lefthalf.filled"
        case .updateAbout: "info.circle"
        }
    }
}

enum SettingsDocument: String, CaseIterable, Identifiable {
    case changelog = "更新日志", legal = "法律与隐私"
    var id: String { rawValue }
}

struct AppSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @Binding var selection: SettingsSection
    @State private var document: SettingsDocument = .changelog

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            selection = section
                        } label: {
                            Label(section.title, systemImage: section.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                                .background(selection == section ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 240, maxHeight: .infinity)
            .background(.bar)

            settingsDetail
                .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, idealWidth: 920, minHeight: 560, idealHeight: 680)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        Group {
            switch selection {
            case .overview: OverviewSettingsView()
            case .highestProtection: ProtectionSettingsView()
            case .account: UserManagementView(embedded: true)
            case .securityLogs: SecurityLogSettingsView()
            case .backup: BackupSettingsView()
            case .appearance: AppearanceSettingsView()
            case .updateAbout:
                VStack(spacing: 0) {
                    Picker("内容", selection: $document) {
                        ForEach(SettingsDocument.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 260, height: 30).padding(.top, 18)
                    if document == .changelog { ChangelogView(embedded: true).transition(.opacity) }
                    else { LegalDisclosureView(embedded: true).transition(.opacity) }
                }
            }
        }
        .environmentObject(store)
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String, subtitle: String
    @ViewBuilder let content: Content
    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 720, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct OverviewSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    var body: some View {
        SettingsPage("安全概览", subtitle: "当前账户和本地保险库的关键状态。") {
            LabeledContent("当前账户", value: store.signedInUsername ?? "未登录")
            LabeledContent("保护模式", value: store.currentAccountAdvancedDataProtectionEnabled ? "最高保护" : "标准保护")
            LabeledContent("加密笔记", value: "\(store.notes.count) 条")
            LabeledContent("保险柜文件", value: "\(store.vaultItems.count) 个")
            Divider()
            Picker("自动锁定", selection: Binding(get: { store.autoLockMinutes }, set: { store.setStandardAutoLockMinutes($0) })) {
                Text("1 分钟").tag(1); Text("5 分钟").tag(5); Text("15 分钟").tag(15); Text("30 分钟").tag(30)
            }
            .disabled(store.currentAccountAdvancedDataProtectionEnabled)
            Text(store.currentAccountAdvancedDataProtectionEnabled ? "最高保护开启时固定为 1 分钟；关闭后恢复原设置。" : "闲置后自动清除已解锁内容和内存密钥。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { store.rotateRecoveryCode() } label: { Label("生成新恢复码", systemImage: "key.fill") }
                Button(role: .destructive) { store.lock() } label: { Label("立即锁定", systemImage: "lock.fill") }
            }
        }
    }
}

private struct ProtectionSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var realPassword = ""
    @State private var decoyPassword = ""
    @State private var confirmation = ""
    @State private var action: DecoyPasswordAction = .openDecoySpace
    @State private var revealDestructiveMode = false
    var body: some View {
        SettingsPage("最高保护", subtitle: "限制解锁后的明文出口，并在窗口失焦时遮挡内容。") {
            VStack(alignment: .leading, spacing: 12) {
                Label(store.currentAccountAdvancedDataProtectionEnabled ? "最高保护已开启" : "当前为标准保护", systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield")
                    .font(.title3.weight(.semibold)).foregroundStyle(store.currentAccountAdvancedDataProtectionEnabled ? .green : .primary)
                Text(store.currentAccountAdvancedDataProtectionEnabled ? "外部打开、复制、普通导出和共享已阻止；自动锁定固定为 1 分钟。" : "标准保护仍会加密磁盘数据，但解锁后允许复制、导出和共享。")
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    withAnimation(MotionStyle.animation(reduceMotion: reduceMotion)) { store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled) }
                } label: {
                    Label(store.currentAccountAdvancedDataProtectionEnabled ? "关闭最高保护" : "开启最高保护", systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.slash" : "shield.lefthalf.filled")
                }
                .buttonStyle(.borderedProminent).tint(store.currentAccountAdvancedDataProtectionEnabled ? .red : .accentColor)
            }
            .padding(16).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            if store.currentAccountAdvancedDataProtectionEnabled {
                Divider()
                Label("虚假密码与虚假空间", systemImage: "theatermasks.fill").font(.headline)
                Text("虚假密码不会打开真实保险库。默认进入可独立保存内容的虚假空间。")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("当前账户真实密码", text: $realPassword)
                SecureField("虚假密码", text: $decoyPassword)
                SecureField("再次输入虚假密码", text: $confirmation)
                Toggle("显示不可逆销毁策略", isOn: $revealDestructiveMode)
                if revealDestructiveMode {
                    Picker("触发后", selection: $action) {
                        Text(DecoyPasswordAction.openDecoySpace.label).tag(DecoyPasswordAction.openDecoySpace)
                        Text(DecoyPasswordAction.eraseLocalData.label).tag(DecoyPasswordAction.eraseLocalData)
                    }
                    Label("销毁策略会删除本机保险库，无法撤销。", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button(store.currentAccountDecoyPasswordEnabled ? "更新虚假密码" : "设置虚假密码") {
                        store.setDecoyPasswordForCurrentAccount(currentPassword: realPassword, decoyPassword: decoyPassword, confirmation: confirmation, action: revealDestructiveMode ? action : .openDecoySpace)
                    }
                    .buttonStyle(.borderedProminent).disabled(realPassword.isEmpty || decoyPassword.isEmpty || confirmation.isEmpty)
                    if store.currentAccountDecoyPasswordEnabled { Button("关闭虚假密码", role: .destructive, action: disableDecoyPassword) }
                }
                ErrorText(store.errorMessage)
            }
        }
    }
    private func disableDecoyPassword() {
        guard let auth = requestDangerAuthorization(title: "关闭虚假密码？", message: "请输入当前账户密码，并输入“关闭虚假密码”继续。", confirmationPrompt: "输入：关闭虚假密码") else { return }
        store.disableDecoyPasswordForCurrentAccount(currentPassword: auth.password, confirmationText: auth.confirmation)
    }
}

private struct SecurityLogSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var filter: SecurityLogCategory = .all
    @State private var showingAuthorization = false
    @State private var password = ""
    private var logs: [SecurityLogEntry] { store.securityLogs.filter { filter == .all || $0.eventType.category == filter } }
    var body: some View {
        SettingsPage("安全日志", subtitle: "日志随当前账户加密保存，不记录正文、文件名、密码或恢复码。") {
            Toggle("记录本地安全事件", isOn: Binding(get: { store.currentAccountSecurityLoggingEnabled }, set: { store.setSecurityLoggingForCurrentAccount($0) }))
            Picker("筛选", selection: $filter) { ForEach(SecurityLogCategory.allCases) { Text($0.label).tag($0) } }
            if logs.isEmpty { ContentUnavailableView("暂无安全日志", systemImage: "checkmark.shield").frame(minHeight: 180) }
            else {
                LazyVStack(spacing: 0) {
                    ForEach(logs.prefix(40)) { log in
                        SettingsSecurityLogRow(log: log)
                        Divider()
                    }
                }
            }
            HStack { Spacer(); Button("清空安全日志", role: .destructive) { password = ""; showingAuthorization = true }.disabled(store.securityLogs.isEmpty) }
        }
        .sheet(isPresented: $showingAuthorization) {
            ClearSettingsLogAuthorization(password: $password) {
                if store.clearSecurityLogs(currentPassword: password) { showingAuthorization = false; password = "" }
            }.environmentObject(store)
        }
    }
}

private struct SettingsSecurityLogRow: View {
    let log: SecurityLogEntry
    private var symbol: String { log.result == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    private var tint: Color { log.result == .success ? .green : .orange }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.eventType.label).font(.callout.weight(.medium))
                Text(log.message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(log.timestamp, style: .relative).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
    }
}

private struct ClearSettingsLogAuthorization: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Binding var password: String
    let confirm: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("清空安全日志", systemImage: "trash.fill").font(.title3.bold()).foregroundStyle(.red)
            Text("请输入当前账户密码。此操作不会删除笔记或保险柜文件。").font(.callout).foregroundStyle(.secondary)
            SecureField("当前账户密码", text: $password).focused($focused)
            ErrorText(store.errorMessage)
            HStack { Button("取消") { dismiss() }; Spacer(); Button("清空", role: .destructive, action: confirm).disabled(password.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420).onAppear { focused = true }
    }
}

private struct BackupSettingsView: View {
    @EnvironmentObject private var store: VaultStore
    var body: some View {
        SettingsPage("备份", subtitle: "备份包含加密保险库与附件，不会生成明文副本。") {
            LabeledContent("数据位置", value: store.vaultStoragePath)
            LabeledContent("加密文件总量", value: ByteCountFormatter.string(fromByteCount: Int64(store.encryptedVaultByteCount), countStyle: .file))
            if let updatedAt = store.vaultFileUpdatedAt { LabeledContent("最近保存", value: updatedAt.formatted(date: .abbreviated, time: .shortened)) }
            Divider()
            HStack {
                Button { backup() } label: { Label("备份保险库", systemImage: "square.and.arrow.up") }
                Button { restore() } label: { Label("从备份还原", systemImage: "arrow.counterclockwise") }
                Spacer(); Button { copyPath() } label: { Image(systemName: "doc.on.doc") }.help("复制数据位置")
            }
            ErrorText(store.errorMessage)
        }
    }
    private func backup() { let panel = NSSavePanel(); panel.nameFieldStringValue = "密笺备份"; panel.canCreateDirectories = true; guard panel.runModal() == .OK, let url = panel.url else { return }; store.backupVault(to: url) }
    private func restore() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; guard panel.runModal() == .OK, let url = panel.url else { return }; guard let auth = requestDangerAuthorization(title: "从备份还原？", message: "这会覆盖当前保险库。请输入密码和确认文字。", confirmationPrompt: "输入：还原保险库") else { return }; store.restoreVault(from: url, currentPassword: auth.password, confirmationText: auth.confirmation) }
    private func copyPath() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.vaultStoragePath, forType: .string); store.showFeedback(.success, title: "数据位置已复制") }
}

private struct AppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("reduceMotion") private var reduceMotion = false
    var body: some View {
        Form {
            Section("外观") { Picker("主题", selection: $appearanceRawValue) { ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented); Text("默认跟随 macOS 外观与系统强调色。").font(.caption).foregroundStyle(.secondary) }
            Section("动态效果") { Toggle("减少动态效果", isOn: $reduceMotion); Text(reduceMotion ? "仅保留短淡入，关闭位移与缩放。" : "使用短弹簧和淡入反馈，不改变控件尺寸。").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).padding(.horizontal, 20)
    }
}
