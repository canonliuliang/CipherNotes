import AppKit
import Foundation
import SwiftUI

struct RecoveryCodeView: View {
    let code: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("保存你的恢复码", systemImage: "key.fill")
                .font(.title2.bold())
            Text("这串恢复码只显示一次。忘记用户密码时，可以用它重设密码；不要把它放在密笺自己的笔记里。")
                .foregroundStyle(.secondary)
            Text(code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            Text("重设密码或重新生成恢复码后，旧恢复码会失效。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("我已保存") { onDone() }
                    .buttonStyle(AppleProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct LegalDisclosureView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("法律与隐私声明", systemImage: "scroll.fill")
                .font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("密笺是本地加密记事工具，不提供法律、财务、医疗、合规或取证建议。你在应用中保存、导入、导出或共享的内容由你自行负责。")
                    Label("可以保护的场景", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("密笺用于保护锁定状态下的本地笔记和保险柜文件，降低他人直接打开应用、复制保险库文件、外部应用留下最近项目，以及保存或还原中断导致数据损坏的风险。强密码和开启 FileVault 仍然十分重要。")
                    Label("无法承诺的场景", systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("密笺不能保证抵抗已解锁 Mac 上的 root 或恶意软件、键盘记录、屏幕采集、实时内存与交换文件取证，也不能在现代 SSD 上证明单个已删文件已被物理擦除。锁定后的密钥覆盖和缓存清理属于尽力而为。")
                    Text("应用不上传笔记、不提供云端恢复，也不保存明文用户密码、恢复码或共享密码。为方便登录页选择账户，账户显示名会保存在本机保险库文件中。忘记用户密码且没有恢复码时，相关笔记可能无法恢复。")
                    Text("最高保护模式会减少应用内预览、导出、复制、外部打开和失焦暴露，但它不是法律豁免、反取证承诺或对抗恶意软件的保证。应用允许用户通过 macOS 截屏、录屏或会议共享捕获当前可见窗口；拥有系统权限的恶意程序、键盘记录、内存取证、备份软件或系统级日志也仍可能造成泄露。")
                    Text("虚假密码和虚假空间用于降低被旁观或被迫临时解锁时的暴露风险；如果你选择销毁本地数据，该操作不可撤销。请自行确认这种设置是否符合你的法律义务、组织规定和实际风险。")
                    Text("在其他 App 中打开、导出或共享文件可能留下最近项目、缓存、缩略图、下载记录或收件记录。密笺只能控制自身行为，不能保证第三方 App 或操作系统组件不留下痕迹。")
                    Text("共享文件采用你输入的共享密码加密；如果共享密码过短、重复使用或通过不安全渠道发送，可能降低保护强度。请只共享你有权共享的内容。")
                    Text("本应用按“现状”提供，不保证适用于任何特定用途。使用前请自行确认是否符合你的组织、地区和行业要求。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("我知道了") { dismiss() }
                    .buttonStyle(AppleProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 520)
    }
}

struct SecurityCenterView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var selectedLogCategory: SecurityLogCategory = .all
    @State private var decoyCurrentPassword = ""
    @State private var decoyPassword = ""
    @State private var decoyConfirmation = ""
    @State private var decoyAction: DecoyPasswordAction = .openDecoySpace
    @State private var showDecoyDestructiveMode = false
    @State private var updateCheckMessage = "尚未检查"
    @State private var isCheckingForUpdates = false

    private var storeErrorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isPresented in
                if !isPresented { store.errorMessage = nil }
            }
        )
    }

    private var filteredSecurityLogs: [SecurityLogEntry] {
        store.securityLogs.filter { log in
            selectedLogCategory == .all || log.eventType.category == selectedLogCategory
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全中心", systemImage: "shield.checkered")
                        .font(.title2.bold())
                    Text("集中查看当前账户、本地保险库和恢复能力。所有操作都只在这台 Mac 上完成。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
                        securityMetric("当前账户", store.signedInUsername ?? "未登录", "person.crop.circle.fill", .mint)
                        securityMetric("账户模型", "平等账户", "person.2.fill", .blue)
                        securityMetric("笔记", "\(store.notes.count) 条", "note.text", .indigo)
                        securityMetric("保险柜", "\(store.vaultItems.count) 个文件", "lock.rectangle.stack.fill", .teal)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("保护状态", systemImage: "checkmark.shield.fill")
                        securityRow(
                            title: "最高保护模式",
                            value: store.currentAccountAdvancedDataProtectionEnabled ? "已开启" : "未开启",
                            systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield",
                            tint: store.currentAccountAdvancedDataProtectionEnabled ? .mint : .secondary
                        )
                        securityRow(
                            title: "自动锁定",
                            value: "\(store.autoLockMinutes) 分钟",
                            systemImage: "timer",
                            tint: .secondary
                        )
                        if store.currentAccountAdvancedDataProtectionEnabled {
                            securityRow(
                                title: "虚假密码",
                                value: store.currentAccountDecoyPasswordEnabled ? "已开启 · \(store.currentAccountDecoyPasswordAction.label)" : "未开启",
                                systemImage: "theatermasks.fill",
                                tint: store.currentAccountDecoyPasswordEnabled ? .orange : .secondary
                            )
                            .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                        }
                        Picker("自动锁定", selection: $store.autoLockMinutes) {
                            Text("1 分钟").tag(1)
                            Text("5 分钟").tag(5)
                            Text("15 分钟").tag(15)
                            Text("30 分钟").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .disabled(store.currentAccountAdvancedDataProtectionEnabled)
                        if store.currentAccountAdvancedDataProtectionEnabled {
                            Text("最高保护模式开启时，自动锁定固定为 1 分钟。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .securitySection()

                    advancedProtectionModeCard

                    if store.currentAccountAdvancedDataProtectionEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("虚假密码", systemImage: "theatermasks.fill")
                            Text("输入虚假密码时，不会打开真实保险库。默认进入虚假空间，不读写真实数据。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("当前账户真实密码", text: $decoyCurrentPassword)
                                .textFieldStyle(.roundedBorder)
                            SecureField("虚假密码", text: $decoyPassword)
                                .textFieldStyle(.roundedBorder)
                            SecureField("再次输入虚假密码", text: $decoyConfirmation)
                                .textFieldStyle(.roundedBorder)
                            Picker("触发后", selection: $decoyAction) {
                                Text(DecoyPasswordAction.openDecoySpace.label).tag(DecoyPasswordAction.openDecoySpace)
                                if showDecoyDestructiveMode {
                                    Text(DecoyPasswordAction.eraseLocalData.label).tag(DecoyPasswordAction.eraseLocalData)
                                }
                            }
                            .pickerStyle(.segmented)
                            Toggle("显示销毁模式", isOn: Binding(
                                get: { showDecoyDestructiveMode },
                                set: { value in
                                    showDecoyDestructiveMode = value
                                    if !value && decoyAction == .eraseLocalData {
                                        decoyAction = .openDecoySpace
                                    }
                                }
                            ))
                            .font(.caption)
                            if showDecoyDestructiveMode {
                                Label(decoyAction == .eraseLocalData ? "销毁模式命中后会删除本机保险库和保险柜附件，无法撤销。" : "销毁模式只适合极端场景，默认不建议开启。", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(decoyAction == .eraseLocalData ? .red : .orange)
                            }
                            HStack {
                                Button {
                                    store.setDecoyPasswordForCurrentAccount(
                                        currentPassword: decoyCurrentPassword,
                                        decoyPassword: decoyPassword,
                                        confirmation: decoyConfirmation,
                                        action: decoyAction
                                    )
                                    if store.errorMessage == "虚假密码已设置" {
                                        decoyCurrentPassword = ""
                                        decoyPassword = ""
                                        decoyConfirmation = ""
                                    }
                                } label: {
                                    Label(store.currentAccountDecoyPasswordEnabled ? "更新虚假密码" : "设置虚假密码", systemImage: "key.horizontal.fill")
                                }
                                .buttonStyle(AppleProminentButtonStyle())
                                .disabled(decoyCurrentPassword.isEmpty || decoyPassword.isEmpty || decoyConfirmation.isEmpty)

                                Button(role: .destructive) {
                                    disableDecoyPassword()
                                } label: {
                                    Label("关闭虚假密码", systemImage: "xmark.shield")
                                }
                                .disabled(!store.currentAccountDecoyPasswordEnabled)
                            }
                        }
                        .securitySection()
                        .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("账户恢复", systemImage: "key.fill")
                        Text("恢复码只在生成时显示一次。重新生成后，旧恢复码会立即失效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            store.rotateRecoveryCode()
                        } label: {
                            Label("生成新的恢复码", systemImage: "key.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    .securitySection()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionTitle("安全日志", systemImage: "list.bullet.rectangle.portrait.fill")
                            Spacer()
                            Toggle("记录", isOn: Binding(
                                get: { store.currentAccountSecurityLoggingEnabled },
                                set: { store.setSecurityLoggingForCurrentAccount($0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            Picker("筛选", selection: $selectedLogCategory) {
                                ForEach(SecurityLogCategory.allCases) { category in
                                    Text(category.label).tag(category)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        Text(store.currentAccountSecurityLoggingEnabled
                             ? "日志随当前账户加密保存，只记录事件、时间和结果，不记录笔记正文、文件内容、密码或恢复码。"
                             : "安全日志已关闭。现有记录仍保留，但应用不会继续新增记录。")
                            .font(.caption)
                            .foregroundStyle(store.currentAccountSecurityLoggingEnabled ? Color.secondary : Color.orange)
                        if filteredSecurityLogs.isEmpty {
                            ContentUnavailableView("暂无安全日志", systemImage: "checkmark.shield")
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(filteredSecurityLogs.prefix(40)) { log in
                                    SecurityLogRow(log: log)
                                }
                            }
                        }
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                clearSecurityLogs()
                            } label: {
                                Label("清空安全日志", systemImage: "trash")
                            }
                            .disabled(store.securityLogs.isEmpty)
                        }
                    }
                    .securitySection()

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("备份与本地数据", systemImage: "externaldrive.fill.badge.timemachine")
                        securityRow(
                            title: "本地数据位置",
                            value: store.vaultStoragePath,
                            systemImage: "folder.fill",
                            tint: .secondary
                        )
                        securityRow(
                            title: "保险柜文件总量",
                            value: ByteCountFormatter.string(fromByteCount: Int64(store.encryptedVaultByteCount), countStyle: .file),
                            systemImage: "internaldrive.fill",
                            tint: .secondary
                        )
                        if let updatedAt = store.vaultFileUpdatedAt {
                            securityRow(
                                title: "保险库更新时间",
                                value: updatedAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "clock.fill",
                                tint: .secondary
                            )
                        }
                        backupActionButtons
                        .buttonStyle(ClearButtonStyle())
                    }
                    .securitySection()

                    versionUpdateCard
                }
                .padding(.vertical, 2)
            }

            HStack {
                Button(role: .destructive) {
                    store.lock()
                    dismiss()
                } label: {
                    Label("立即锁定", systemImage: "lock.fill")
                }
                Spacer()
                ErrorText(store.errorMessage)
            }
        }
        .padding(24)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 640, idealHeight: 720)
        .alert("密笺", isPresented: storeErrorPresented) {
            Button("好") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var backupActionButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
            Button {
                backupVault()
            } label: {
                Label("备份保险库", systemImage: "square.and.arrow.up")
            }
            Button {
                restoreVault()
            } label: {
                Label("从备份还原", systemImage: "arrow.counterclockwise")
            }
            Button {
                copyVaultPath()
            } label: {
                Label("复制数据位置", systemImage: "doc.on.doc")
            }
        }
    }

    private var versionUpdateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("版本与更新", systemImage: "arrow.down.circle.fill")
            securityRow(
                title: "当前版本",
                value: "\(currentAppVersion) (\(currentAppBuild))",
                systemImage: "app.badge",
                tint: .secondary
            )
            securityRow(
                title: "最新版本",
                value: updateCheckMessage,
                systemImage: "arrow.triangle.2.circlepath.circle",
                tint: isCheckingForUpdates ? .orange : .secondary
            )
            Text("检查更新只会手动访问 GitHub Releases latest，不上传笔记、账户、日志或本地数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            updateButtons
            .buttonStyle(ClearButtonStyle())
        }
        .securitySection()
    }

    private var updateButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
            Button {
                checkForLatestRelease()
            } label: {
                Label(isCheckingForUpdates ? "正在检查" : "检查更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isCheckingForUpdates)
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/canonliuliang/CipherNotes/releases/latest")!)
            } label: {
                Label("打开最新版下载页", systemImage: "arrow.down.circle")
            }
            Button {
                NSWorkspace.shared.open(URL(string: "https://canonliuliang.github.io/CipherNotes/")!)
            } label: {
                Label("打开官网", systemImage: "safari")
            }
        }
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    private var currentAppBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    private func checkForLatestRelease() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        updateCheckMessage = "正在连接 GitHub..."
        Task {
            do {
                let release = try await fetchLatestRelease()
                await MainActor.run {
                    let tag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                    if tag == currentAppVersion {
                        updateCheckMessage = "已是最新版 · \(release.name)"
                    } else {
                        updateCheckMessage = "发现 \(release.tagName) · \(release.name)"
                    }
                    isCheckingForUpdates = false
                }
            } catch {
                await MainActor.run {
                    updateCheckMessage = "检查失败，可直接打开下载页"
                    isCheckingForUpdates = false
                }
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubLatestRelease {
        let url = URL(string: "https://api.github.com/repos/canonliuliang/CipherNotes/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
    }

    private func securityMetric(_ title: String, _ value: String, _ systemImage: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var advancedProtectionModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield")
                    .font(.title2)
                    .foregroundStyle(store.currentAccountAdvancedDataProtectionEnabled ? .mint : .secondary)
                    .frame(width: 28)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentAccountAdvancedDataProtectionEnabled ? "最高保护模式正在运行" : "最高保护模式未开启")
                        .font(.headline)
                        .contentTransition(.opacity)
                    Text(store.currentAccountAdvancedDataProtectionEnabled ? "文件只在密笺内解密查看，不交给外部 App；复制、导出、共享、外部预览和文件名复制都会被阻止。" : "适合在设备可能离开你手边、借用设备、展示屏幕或处理敏感文件前开启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                protectionCapability("自动锁定", "1 分钟", "timer")
                protectionCapability("内置查看", "不交外部 App", "eye.fill")
                protectionCapability("阻止导出", "明文不落盘", "square.and.arrow.up")
                protectionCapability("脱敏日志", "不暴露名称", "list.bullet.rectangle")
            }

            Button {
                store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
            } label: {
                Label(store.currentAccountAdvancedDataProtectionEnabled ? "关闭最高保护模式" : "开启最高保护模式", systemImage: "shield.lefthalf.filled")
            }
            .buttonStyle(ClearButtonStyle(prominence: store.currentAccountAdvancedDataProtectionEnabled ? .danger : .primary))
            .controlSize(.large)
        }
        .securitySection()
        .animation(
            MotionStyle.animation(reduceMotion: reduceMotion),
            value: store.currentAccountAdvancedDataProtectionEnabled
        )
    }

    private func protectionCapability(_ title: String, _ value: String, _ systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.mint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func securityRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 16)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func backupVault() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "密笺备份"
        panel.canCreateDirectories = true
        panel.message = "选择一个位置保存本地加密保险库备份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.backupVault(to: url)
    }

    private func restoreVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择备份"
        panel.message = "请选择包含 vault.json 的密笺备份文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "从备份还原保险库？"
        alert.informativeText = "这会覆盖当前保险库。当前未备份的笔记和保险柜文件将永久丢失。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "还原")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let auth = requestDangerAuthorization(
            title: "确认当前账户",
            message: "请输入当前账户密码，并输入“还原保险库”继续。",
            confirmationPrompt: "输入：还原保险库"
        ) else { return }
        store.restoreVault(from: url, currentPassword: auth.password, confirmationText: auth.confirmation)
    }

    private func copyVaultPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.vaultStoragePath, forType: .string)
        store.errorMessage = "本地数据位置已复制"
    }

    private func clearSecurityLogs() {
        guard let password = requestPasswordAuthorization(
            title: "清空安全日志？",
            message: "这只会清空当前账户的本地安全日志，不会删除笔记或保险柜文件。请输入当前账户密码继续。",
            actionTitle: "清空"
        ) else { return }
        store.clearSecurityLogs(currentPassword: password)
    }

    private func disableDecoyPassword() {
        let alert = NSAlert()
        alert.messageText = "关闭虚假密码？"
        alert.informativeText = "关闭后，虚假密码将不再进入虚假空间或触发销毁策略。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let auth = requestDangerAuthorization(
            title: "确认关闭虚假密码",
            message: "请输入当前账户密码，并输入“关闭虚假密码”继续。",
            confirmationPrompt: "输入：关闭虚假密码"
        ) else { return }
        store.disableDecoyPasswordForCurrentAccount(currentPassword: auth.password, confirmationText: auth.confirmation)
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
    }
}

struct SecurityLogRow: View {
    let log: SecurityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(log.eventType.label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(log.result.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                Text(log.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(log.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
        }
        .padding(10)
        .nativeGlassSurface(radius: 12)
    }

    private var iconName: String {
        switch log.eventType.category {
        case .all:
            "checkmark.shield"
        case .login:
            "lock.open.fill"
        case .account:
            "person.crop.circle.badge.checkmark"
        case .advancedProtection:
            "shield.lefthalf.filled"
        case .transfer:
            "arrow.up.arrow.down"
        case .vault:
            "lock.rectangle.stack.fill"
        case .danger:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch log.result {
        case .success:
            .mint
        case .failure:
            .orange
        case .blocked:
            .red
        }
    }
}

private extension View {
    func securitySection() -> some View {
        padding(14)
            .nativeGlassSurface(radius: 16)
    }
}

struct UserManagementView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenCipherNotesIntro") private var hasSeenIntro = false
    @State private var passwordCurrent = ""
    @State private var passwordNew = ""
    @State private var passwordConfirmation = ""
    @State private var currentPassword = ""
    @State private var confirmationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("账户与安全", systemImage: "person.2.badge.gearshape")
                        .font(.title2.bold())
                    Text("这台 Mac 上的账户彼此可见，但只能管理当前登录账户。其他账户的数据由各自密码和恢复码保护。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        accountMetric("当前账户", store.signedInUsername ?? "未登录", "person.crop.circle.fill", .mint)
                        accountMetric("本机账户", "\(store.accounts.count) 个", "person.2.fill", .blue)
                        accountMetric("最高保护", store.currentAccountAdvancedDataProtectionEnabled ? "已开启" : "未开启", "shield.lefthalf.filled", store.currentAccountAdvancedDataProtectionEnabled ? .mint : .secondary)
                        accountMetric("虚假密码", store.currentAccountDecoyPasswordEnabled ? "已开启" : "未开启", "theatermasks.fill", store.currentAccountDecoyPasswordEnabled ? .orange : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("本机账户", systemImage: "person.2.fill")
                        Text("你可以查看所有本地账户状态，但只能修改当前登录账户。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if store.accounts.isEmpty {
                            ContentUnavailableView("暂无账户", systemImage: "person.crop.circle.badge.questionmark")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.accounts, id: \.id) { account in
                                    accountRow(account)
                                }
                            }
                        }
                    }
                    .securitySection()

                    passwordSection
                    dangerZone
                    ErrorText(store.errorMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 620, idealHeight: 660)
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("当前账户密码", systemImage: "key.fill")
            Text("修改后会保留当前账户的笔记、保险柜文件和安全日志。新的恢复码会在需要时重新生成。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("当前账户密码", text: $passwordCurrent)
                .textFieldStyle(.roundedBorder)
            SecureField("新账户密码", text: $passwordNew)
                .textFieldStyle(.roundedBorder)
            SecureField("再次输入新账户密码", text: $passwordConfirmation)
                .textFieldStyle(.roundedBorder)
            PasswordStrengthIndicator(password: passwordNew)
            HStack {
                Spacer()
                Button {
                    store.changeCurrentUserPassword(
                        currentPassword: passwordCurrent,
                        newPassword: passwordNew,
                        confirmation: passwordConfirmation
                    )
                    if store.errorMessage == "当前账户密码已更新" {
                        passwordCurrent = ""
                        passwordNew = ""
                        passwordConfirmation = ""
                    }
                } label: {
                    Label("更新密码", systemImage: "key.fill")
                }
                .buttonStyle(AppleProminentButtonStyle())
                .disabled(passwordNew != passwordConfirmation)
            }
        }
        .securitySection()
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("危险操作", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("删除当前账户、清空全部数据都需要当前账户密码、对应确认文字和 macOS 二次确认。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("当前账户密码", text: $currentPassword)
                .textFieldStyle(.roundedBorder)
            TextField("输入确认文字", text: $confirmationText)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 5) {
                Label("删除当前账户：输入“删除我的账户”", systemImage: deleteConfirmationReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(deleteConfirmationReady ? .mint : .secondary)
                Label("清空全部数据：输入“清空全部数据”", systemImage: eraseConfirmationReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(eraseConfirmationReady ? .mint : .secondary)
            }
            .font(.caption)
            ViewThatFits(in: .horizontal) {
                dangerButtons
                VStack(alignment: .leading, spacing: 8) {
                    deleteCurrentAccountButton
                    eraseAllDataButton
                }
            }
        }
        .padding(12)
        .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.red.opacity(0.22), lineWidth: 1)
        }
    }

    private var dangerButtons: some View {
        HStack {
            deleteCurrentAccountButton
            Spacer()
            eraseAllDataButton
        }
    }

    private var deleteConfirmationReady: Bool {
        !currentPassword.isEmpty && confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "删除我的账户"
    }

    private var eraseConfirmationReady: Bool {
        !currentPassword.isEmpty && confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "清空全部数据"
    }

    private var deleteCurrentAccountButton: some View {
        Button("删除当前账户", role: .destructive) {
            guard confirmWithSystem(title: "删除当前账户？", message: "这会永久删除当前账户的笔记、保险柜文件、恢复码包装密钥和虚假空间。") else { return }
            store.deleteCurrentUser(password: currentPassword, confirmationText: confirmationText)
            if store.state == .needsAdminSetup {
                hasSeenIntro = false
            }
            if store.state != .unlocked { dismiss() }
        }
        .disabled(store.currentAccountID == nil || !deleteConfirmationReady)
    }

    private var eraseAllDataButton: some View {
        Button("清空全部数据", role: .destructive) {
            guard confirmWithSystem(title: "清空全部密笺数据？", message: "这会永久删除这台 Mac 上所有密笺账户、笔记和保险柜文件。") else { return }
            store.eraseAllDataAndStartFresh(currentPassword: currentPassword, confirmationText: confirmationText)
            if store.state == .needsAdminSetup {
                hasSeenIntro = false
                currentPassword = ""
                confirmationText = ""
                dismiss()
            }
        }
        .buttonStyle(AppleProminentButtonStyle())
        .disabled(!eraseConfirmationReady)
    }

    private func accountRow(_ account: AccountSummary) -> some View {
        let isCurrent = account.id == store.currentAccountID
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isCurrent ? "当前登录账户，可管理自己的安全设置" : "其他本地账户，只显示状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(
                    account.advancedDataProtectionEnabled ? "最高保护已开启" : "最高保护未开启",
                    systemImage: account.advancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield"
                )
                .font(.caption2)
                .foregroundStyle(account.advancedDataProtectionEnabled ? .mint : .secondary)
                if account.advancedDataProtectionEnabled {
                    Label(
                        account.decoyPasswordEnabled ? "虚假密码已开启" : "虚假密码未开启",
                        systemImage: "theatermasks"
                    )
                    .font(.caption2)
                    .foregroundStyle(account.decoyPasswordEnabled ? .orange : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .nativeGlassSurface(radius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCurrent ? Color.mint.opacity(0.45) : Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func accountMetric(_ title: String, _ value: String, _ systemImage: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func confirmWithSystem(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    private let entries: [UpdateLogEntry] = [
        UpdateLogEntry(
            id: "1.1.15",
            version: "1.1.15",
            title: "安全持久化与原生交互重构",
            dateText: "2026-08-02",
            items: [
                "保险库写入与备份还原加入事务日志、候选文件和回滚恢复，意外中断后会优先恢复最近一次完整有效的数据。",
                "主界面代码拆分为验证、安全中心、持久化、备份、导入、缓存和应用外观等独立模块，降低后续修改的相互影响。",
                "保险柜查看器完善全屏布局、原生锚点缩放、1:1 像素查看、相邻内容预载取消和轻量加载反馈。",
                "工作区建立顶部导航、快速查看面板和内容主体三层结构，移除会导致窗口标题跳动的系统自动侧栏入口。",
                "账户切换、记事本与保险柜切换、保护状态、列表增删和查看器切图加入统一短动效，并完整支持减少动态效果。",
                "应用内更新日志只展示最近 10 个版本，避免历史记录过长影响浏览。",
                "新增本地威胁模型和事务恢复回归测试，发布版本更新为 1.1.15 (52)，48 项自动化测试通过。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.14",
            version: "1.1.14",
            title: "界面入口与状态安全整理",
            dateText: "2026-08-02",
            items: [
                "重新整理主窗口功能层级：工具栏只保留安全中心、应用设置和立即锁定，页面内只显示当前区域相关操作。",
                "移除底部重复快捷栏，以及齿轮菜单、菜单栏和安全中心内重复的最高保护、恢复码与账户入口。",
                "最高保护模式只在安全中心管理；保险柜导入保留在保险柜标题区；笔记命令保留在笔记菜单和所选项目菜单。",
                "固定记事本与保险柜切换器的宽高，去除侧栏重复账户状态，并避免空笔记页同时出现两个新建按钮。",
                "修复锁定状态仍可能打开账户设置，以及自动锁定后安全设置窗口未同步关闭的问题。",
                "发布版本更新为 1.1.14 (51)，完整测试、打包、网站、README 与 GitHub Release 元数据保持一致。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.13",
            version: "1.1.13",
            title: "登录界面重构",
            dateText: "2026-07-26",
            items: [
                "登录、注册和恢复重构为统一的紧凑 macOS 验证界面，全屏与最小窗口都会保持合理居中。",
                "锁定状态不再显示底部工具栏，账户选择合并成一条完整的本地账户菜单。",
                "主操作按钮改为整行宽度，三段选择栏位置固定，下面的玻璃内容区按模式平滑改变高度。",
                "修复首次打开时选择栏与表单内容短暂不一致、切换裁切和玻璃面板空白过大的问题。",
                "新增登录与首次注册快照回归测试，发布版本更新为 1.1.13 (50)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.12",
            version: "1.1.12",
            title: "安全与稳定性修复",
            dateText: "2026-07-25",
            items: [
                "强化最高保护模式的会话隔离，切换安全上下文前会清理当前工作区与敏感预览缓存。",
                "受保护的数据区使用独立加密载荷，并继续兼容已有本地保险库。",
                "清空安全日志改为一次账户密码确认，不再重复弹窗或要求输入固定确认文字。",
                "新增隔离、加密落盘、锁定重登与日志授权回归测试，发布版本更新为 1.1.12 (49)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.11",
            version: "1.1.11",
            title: "全屏查看器适配",
            dateText: "2026-07-25",
            items: [
                "查看器不再使用固定尺寸弹窗，而是覆盖完整保险柜工作区并跟随主窗口实时伸缩。",
                "右上角新增系统全屏切换，进入或退出全屏时不会重新解密当前文件。",
                "适合窗口状态会随视口尺寸重新计算；用户主动放大后则保留当前缩放位置。",
                "新增 1440×900 实际图片区域回归测试，防止只扩大外层而内容仍停留在小窗口。",
                "发布版本更新为 1.1.11 (48)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.10",
            version: "1.1.10",
            title: "原生焦点缩放与查看器修复",
            dateText: "2026-07-25",
            items: [
                "双击图片和 macOS 智能缩放现在会以指针下方的图片像素为锚点，不再固定围绕整张图片中心放大。",
                "放大前后点击像素会保持在指针对应的视口位置，连续检查细节时不需要再次拖动画面。",
                "工具栏缩放继续围绕当前视口中心，适合窗口仍会恢复完整图片。",
                "新增 AppKit 坐标锚定回归测试，发布版本更新为 1.1.10 (47)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.9",
            version: "1.1.9",
            title: "原生媒体查看器与性能重构",
            dateText: "2026-07-21",
            items: [
                "照片、视频、音频、PDF 与文本查看器拆分为独立模块，保险柜列表不再承担预览器生命周期。",
                "大图通过加密随机访问与 ImageIO 按需降采样，不再先把完整文件解密进内存。",
                "图片支持原生触控板捏合、双击、快捷键缩放、窗口变化后自动适配，并在切图时保留上一帧避免闪白。",
                "缩略图改为惰性胶片栏，预载相邻照片；重复查看会复用受控缓存，锁定时立即取消并清空。",
                "视频使用原生播放控件，音频只在拖动结束后定位，离开文件会立即停止播放并释放观察器。",
                "多张普通照片也会在后台导入，避免加密工作阻塞主界面。",
                "旧保险库即使缺少 MIME 信息，也能依据扩展名识别 HEIC、MOV、M4A、PDF 与文本。",
                "发布版本更新为 1.1.9 (46)，39 项自动化测试全部通过。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.8",
            version: "1.1.8",
            title: "照片保险柜与稳定性更新",
            dateText: "2026-07-21",
            items: [
                "保险柜支持全页拖拽导入，移入前明确提示原文件会在加密成功后删除。",
                "新增连续照片与视频查看器，支持左右切换、方向键、缩略图、图片缩放和媒体进度控制。",
                "图片改用 macOS 原生缩放容器，支持触控板捏合、双击缩放、滚动查看和适合窗口，并移除人为触控板震动。",
                "大图在后台解密并按显示尺寸降采样；音视频按需读取加密分块，不写入明文临时文件。",
                "安全日志现在可按账户关闭后续记录，已有的加密日志会保留。",
                "修复登录后主工作区塌缩和底部功能栏覆盖内容的问题。",
                "发布版本更新为 1.1.8 (45)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.7",
            version: "1.1.7",
            title: "允许系统截屏",
            dateText: "2026-07-21",
            items: [
                "移除窗口的系统级截屏与录屏阻止标记，可正常使用 macOS 截图、录屏和会议共享。",
                "最高保护模式继续保留失焦遮罩、自动锁定和敏感预览缓存清理。",
                "法律与隐私声明明确：屏幕捕获由用户与 macOS 控制，应用不会承诺阻止取证或录屏。",
                "1.0.8 主界面与当前登录页保持不变。",
                "发布版本更新为 1.1.7 (42)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.6",
            version: "1.1.6",
            title: "经典界面回归",
            dateText: "2026-07-21",
            items: [
                "笔记、保险柜、查看器、工具栏、设置与安全中心恢复为 1.0.8 的界面结构。",
                "登录、注册和恢复页面完整保留当前版本，固定选择栏与自适应面板动画不变。",
                "保留当前加密数据格式、平等账户模型和后续安全修复，不回退或迁移现有保险库。",
                "仅加入异步图片预览和当前导入任务状态所需的兼容适配。",
                "发布版本更新为 1.1.6 (41)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.7",
            version: "1.0.7",
            title: "macOS 原生界面与 Liquid Glass 收口",
            dateText: "2026-07-13",
            items: [
                "主窗口重新按 macOS 原生层级组织：侧边栏、工具栏、内容区和浮层职责更清楚。",
                "Liquid Glass 只用于按钮、状态面板、日志行和浮动面板；笔记阅读与编辑区域保持清晰的系统背景。",
                "减少自定义渐变、硬边框和厚重阴影，颜色更多跟随系统 accent color，并改善深色模式对比度。",
                "侧边栏改用原生 List sidebar 风格，工具栏改用系统 bar 背景。",
            ]
        ),
        UpdateLogEntry(
            id: "1.0.8",
            version: "1.0.8",
            title: "正式版收口与稳定性优化",
            dateText: "2026-07-14",
            items: [
                "移除独立演示构建、演示保险库和演示发布链路，正式下载只保留一个 App 和一个安装包。",
                "记事本与保险柜切换改为稳定的即时切换，避免页面标题、侧栏和工具栏闪现。",
                "保险柜文件操作改用系统原生菜单，减少受保护文件操作入口的打开延迟。",
                "筛选条、状态条和窗口内容继续固定关键高度，降低窄窗口下的布局跳动。",
                "发布版本统一为 1.0.8，build 统一为 33，并在应用包中记录构建时间。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.6",
            version: "1.0.6",
            title: "安全日志与保护模式收敛",
            dateText: "2026-07-13",
            items: [
                "安全日志最多保留最近 120 条，五秒内重复的同类事件自动合并，安全中心只展示最近 40 条筛选结果。",
                "移除设备级生物识别解锁入口，登录只保留账户密码和恢复码，避免多人共用设备时产生误解。",
                "虚假空间改为独立加密并可保存：虚假密码进入后可以新建笔记和移入保险柜文件，但不会读写真实空间。",
                "最高保护模式的开启与关闭按钮改为不同视觉状态，避免危险操作和保护操作看起来一样。",
                "固定登录页登录/注册/恢复切换栏和内容区高度，切换时不再出现面板跳动。",
                "法律与隐私声明补充威胁边界：本地加密不等于法律、取证或恶意软件防护承诺。",
                "明确版本规则：功能、安全、数据模型或法律文案变化必须升 patch 版本，build 只表示打包迭代。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.4",
            version: "1.0.4",
            title: "危险操作确认与窗口适配",
            dateText: "2026-07-05",
            items: [
                "主界面新增当前账户、保护模式、自动锁定和保险柜状态条，打开后先看状态再操作。",
                "账户与安全延续安全中心的信息层级：状态卡、账户分区、密码分区和危险操作分区更清楚。",
                "高级数据保护改成模式卡，明确显示会收紧自动锁定并阻止复制、导出、共享和预览路径。",
                "虚假密码默认推荐进入虚假空间，直接销毁模式需要主动展开后才可选择。",
                "保险柜导入新增队列和进度条，大文件加密移入时可以看到当前文件和处理进度。",
                "外观切换同步到 AppKit 层，系统菜单、弹窗和保存面板会跟随浅色/深色设置。",
                "提高自定义按钮在浅色和深色模式下的底色对比，减少按钮与背景融为一体。",
                "笔记编辑器新增正在保存/已保存状态和手动保存按钮。",
                "空笔记、无搜索结果和归档为空时提供直接新建入口。",
                "安全中心的快捷操作、备份按钮和更新入口改为自适应布局，窄窗口下不会挤出边界。",
                "新增版本与更新入口，可直接打开 GitHub 最新版下载页和官网。",
                "固定记事本/保险柜主切换条高度，两个区域之间切换不再出现顶部控件跳动。",
                "记事本与保险柜共用同一套窗口工具栏，避免切换时 macOS 重新计算工具栏高度。",
                "笔记侧栏始终显示保护状态，标准保护和高级保护之间切换不再改变侧栏头部高度。",
                "保险柜标题区和文件类型筛选改为稳定自适应布局，常见窗口宽度下不再突然换行。",
                "发布流程新增共享校验脚本，本地打包、CI 和 GitHub Release 会检查版本、README、官网和应用内日志是否一致。",
                "README 增加“为什么选择 CipherNotes”、发布安全检查和大文件保险柜说明，更像正式产品首页。",
                "安全中心新增手动检查更新：显示当前版本/build，并对比 GitHub Releases latest。",
                "保险柜导入队列新增取消导入、剩余时间估计和清除完成记录，处理大文件更安心。",
                "保险柜新增图片、文本和 PDF 内置无落盘查看器，最高保护模式下不用交给外部 App 打开。",
                "保险柜新增常见音频文件的内存播放器，不写临时明文文件，不调用外部播放器。",
                "最高保护模式下窗口离开活动状态会显示隐私遮罩，并清理保险柜预览缓存。",
                "视频文件暂不交给外部 App 打开，后续会单独加入更硬化的无落盘视频播放器。",
                "安全中心将高级数据保护升级为“最高保护模式”文案，强调内置查看、阻止外部导出和锁定清理。",
                "附件目录自动写入 .metadata_never_index，减少 Spotlight 对保险柜密文目录的索引噪音。",
                "账户与安全里的危险操作改为双确认提示：删除当前账户和清空全部数据分别显示自己的确认文字。",
                "当前账户密码和确认文字未满足前，删除/清空按钮保持不可点，减少误操作和无效弹窗。",
                "安全中心和账户与安全窗口改为更弹性的尺寸，减少内容挤压和显示不全。",
                "README、官网、Pages、打包配置和发布说明同步到 1.0.4。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.3",
            version: "1.0.3",
            title: "GitHub 风格官网与发布流程",
            dateText: "2026-07-05",
            items: [
                "官网改为更接近 GitHub 项目首页的布局：仓库标题、Release 卡片、README 内容区、隐私边界和开发流程更清晰。",
                "官网图标换成统一线宽的 SVG 图标，移除粗糙字符图标和旧的 CSS 假图标。",
                "下载入口继续统一指向 GitHub Releases latest，并明确说明 push 源码不等于更新公开下载包。",
                "README、官网、Pages 和本地产品介绍页同步 1.0.3 版本说明。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.2",
            version: "1.0.2",
            title: "虚假密码与清晰按钮",
            dateText: "2026-07-05",
            items: [
                "高级数据保护新增虚假密码：输入虚假密码可进入临时虚假空间，不打开真实保险库。",
                "虚假密码也可设置为直接销毁本地保险库数据，适合极端场景；该模式不可逆，请谨慎开启。",
                "设置和关闭虚假密码都需要当前账户真实密码，应用不会保存明文虚假密码。",
                "提高底部工具栏和关键按钮的对比度，减少按钮与背景融为一体的问题。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.1",
            version: "1.0.1",
            title: "本地安全日志与高级保护收口",
            dateText: "2026-07-05",
            items: [
                "安全中心新增本地安全日志，记录登录、锁定、旧版快捷解锁、高级保护、导入导出和危险操作。",
                "安全日志随当前账户加密保存，不记录笔记正文、文件内容、明文密码、恢复码或敏感文件名。",
                "高级数据保护开启后阻止复制、普通导出、共享导入导出、保险柜预览、保险柜导出和复制保险柜文件名。",
                "移除 Apple 密码 App 辅助保存入口，避免钥匙串权限错误影响体验。",
                "README 和官网改成更正式的产品展示，下载入口统一指向 GitHub Releases latest。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.0",
            version: "1.0.0",
            title: "纯免费版本与平等本地账户",
            dateText: "2026-07-04",
            items: [
                "移除会员、购买、恢复购买和所有付费门槛，现有本地功能全部免费可用。",
                "注册页不再出现会员等级；高级数据保护和恢复码重生成变为普通安全功能。",
                "账户与安全改为平等本地账户模型：账户可见但只能管理自己，危险操作需要当前账户密码和确认文字。",
                "新增一键 release 打包脚本，自动测试、构建并更新 app、pkg、zip、说明文档和图标。",
                "重绘应用图标，改为现代简约的蓝青 Fluent 风格。",
                "新增安全中心，集中查看账号保护状态、自动锁定、旧版快捷解锁、恢复码、备份还原和本地数据位置。",
                "保险柜改为分片加密存储，超大文件会后台导入并支持流式导出，不再一次性读入内存。",
                "优化保险柜大图预览、文件权限访问和发布打包流程，减少卡顿与权限噪音。",
                "新增首次创建保险库、旧版快捷解锁 解锁、保险柜导入和加密完成时的轻量动效与反馈。",
                "保留首次简介、应用内更新日志、法律声明、备份还原、保险柜和共享文件等已有功能。"
            ]
        ),
        UpdateLogEntry(
            id: "0.10.1",
            version: "0.10.1",
            title: "保险库备份还原与残留文件自动清理",
            dateText: "2026-06-27",
            items: [
                "新增保险库全量备份：可将 vault.json 和全部加密附件复制到自选文件夹。",
                "新增从备份还原保险库的功能，还原前会二次确认并自动锁定当前保险库。",
                "启动时自动扫描并清理已注销用户的残留加密附件文件，避免磁盘泄漏。",
                "备份和还原入口位于菜单栏「保险库」菜单中。"
            ]
        ),
        UpdateLogEntry(
            id: "0.10.0",
            version: "0.10.0",
            title: "多账户与安全能力整理",
            dateText: "2026-06-27",
            items: [
                "首次打开新增应用简介，引导用户理解本地加密、多账号和隐私边界。",
                "创建账号时开始整理多账户模型。",
                "账户内容由各自密码保护，其他账户不能查看用户笔记。",
                "高级数据保护、恢复码重生成、保险柜、导入导出等能力均作为本地免费功能提供。"
            ]
        ),
        UpdateLogEntry(
            id: "0.9.1",
            version: "0.9.1",
            title: "高级数据保护账号",
            dateText: "2026-06-27",
            items: [
                "新增账号级高级数据保护开关，每个本地用户可单独开启。",
                "开启后笔记列表隐藏正文预览，避免旁人从列表扫到内容。",
                "开启后自动锁定收紧到 1 分钟，重新登录该账号后仍会保持。",
                "账户列表会显示每个账号的高级数据保护状态，其他账户仍不能查看用户数据。"
            ]
        ),
        UpdateLogEntry(
            id: "0.9.0",
            version: "0.9.0",
            title: "大量日常功能：组织、写作、导出与保险柜管理",
            dateText: "2026-06-27",
            items: [
                "新增笔记置顶、收藏、归档和标签，老保险库会自动兼容默认值。",
                "新增全部 / 收藏 / 置顶 / 归档筛选，排序增加收藏优先。",
                "编辑器新增 Markdown 预览、标签输入、词数、行数和预计阅读时间。",
                "新增 Markdown / TXT 普通导出，并补充对应顶部菜单快捷入口。",
                "保险柜新增类型筛选、总容量统计和复制文件名。"
            ]
        ),
        UpdateLogEntry(
            id: "0.8.1",
            version: "0.8.1",
            title: "旧版快捷解锁 迁移、登录细节与 macOS 质感修补",
            dateText: "2026-06-27",
            items: [
                "旧版 旧版快捷解锁 用户可在密码登录成功后直接启用 / 修复新版 旧版快捷解锁，不再像功能凭空消失。",
                "登录失败不再清空密码，减少输错一个字符就重来的挫败感。",
                "重做玻璃面板层次：使用更接近 macOS 的 material、边框高光、底栏分隔和克制阴影。",
                "补上登录页、记事本 / 保险柜切换、保险柜卡片的过渡与 hover 反馈。"
            ]
        ),
        UpdateLogEntry(
            id: "0.8.0",
            version: "0.8.0",
            title: "钥匙串弹窗修复与克制动效",
            dateText: "2026-06-27",
            items: [
                "旧版快捷解锁 状态改为保险库元数据，登录页和账户管理不再为了显示按钮读取钥匙串。",
                "新 旧版快捷解锁 使用 app.ciphernotes.person.crop.circle-v2，旧 旧版快捷解锁 用户需用密码登录后重新启用一次。",
                "新增克制过渡动效和减少动效设置。"
            ]
        ),
        UpdateLogEntry(
            id: "0.7.1",
            version: "0.7.1",
            title: "真正独立的照片/文件保险柜",
            dateText: "2026-06-27",
            items: [
                "照片和文件不再挂在某条笔记下面，而是进入独立保险柜区域。",
                "移入保险柜会先加密保存，成功后删除原照片/原文件。",
                "锁定后清空保险柜内存列表，重新登录后再恢复加密文件。",
                "菜单栏入口改为保险库里的“移入照片或文件…”。"
            ]
        ),
        UpdateLogEntry(
            id: "0.7.0",
            version: "0.7.0",
            title: "加密文件保险箱",
            dateText: "2026-06-27",
            items: [
                "新增图片和任意文件附件；图片可预览，文件可导出或删除。",
                "附件以独立加密文件块保存，编辑文字时不再反复重写大文件。",
                "共享 .ciphernote 文件现在可以携带附件，导入后进入当前用户自己的保险箱。",
                "自动保存改为更安静的延迟保存，减少输入时的打扰和磁盘写入。"
            ]
        ),
        UpdateLogEntry(
            id: "0.6.2",
            version: "0.6.2",
            title: "窗口、旧版快捷解锁、安全提示与菜单栏增强",
            dateText: "2026-06-27",
            items: [
                "修复底部按钮可能遮挡内容的窗口显示问题，并恢复标准窗口标题栏。",
                "明确 旧版快捷解锁 是 macOS 设备级验证；每个账户独立保存快捷解锁密钥，可单独关闭。",
                "新增笔记排序、复制内容、复制为新笔记、编辑器统计与延迟保存。",
                "完善顶部菜单栏：笔记、保险库、外观和帮助入口更完整。"
            ]
        ),
        UpdateLogEntry(
            id: "0.6.1",
            version: "0.6.1",
            title: "删除用户修复与外观跟随系统",
            dateText: "2026-06-27",
            items: [
                "修复删除用户后界面状态可能没有同步刷新的问题。",
                "账户管理改为窗口内二次确认，删除流程更清楚、更可靠。",
                "新增外观选择：跟随系统、浅色、深色。"
            ]
        ),
        UpdateLogEntry(
            id: "0.6.0",
            version: "0.6.0",
            title: "无账号密码限制与账户删除",
            dateText: "2026-06-27",
            items: [
                "取消用户名格式、用户名长度和密码长度限制，空用户名会显示为“未命名账户”。",
                "账户删除只销毁数据，不能查看用户笔记。",
                "优化按钮禁用、提示文案和误删确认，让流程更贴近真实使用。"
            ]
        ),
        UpdateLogEntry(
            id: "0.5.0",
            version: "0.5.0",
            title: "账户选择、旧版快捷解锁 与更新日志",
            dateText: "2026-06-27",
            items: [
                "注册和旧数据迁移时可选择为账户启用 旧版快捷解锁。",
                "登录页改为先选择账户，再用密码或 旧版快捷解锁 登录。",
                "新增更新日志入口，方便查看最近变化。"
            ]
        ),
        UpdateLogEntry(
            id: "0.4.0",
            version: "0.4.0",
            title: "共享文件与界面更新",
            dateText: "2026-06-26",
            items: [
                "新增 .ciphernote 加密共享文件导入/导出。",
                "增加法律与隐私声明。",
                "优化暗色玻璃质感界面。"
            ]
        ),
        UpdateLogEntry(
            id: "0.3.1",
            version: "0.3.1",
            title: "恢复码与旧数据处理",
            dateText: "2026-06-26",
            items: [
                "注册和迁移后显示一次性恢复码。",
                "可用恢复码重设用户密码并保留笔记。",
                "旧保险库升级页增加跳过并清空旧数据。"
            ]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("更新日志", systemImage: "sparkles")
                    .font(.title2.bold())
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/canonliuliang/CipherNotes/releases/latest")!)
                } label: {
                    Label("最新版下载页", systemImage: "arrow.down.circle")
                }
                .buttonStyle(ClearButtonStyle())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("最近 10 个版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(entries.prefix(10))) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.version).font(.headline).foregroundStyle(.mint)
                                Text(entry.title).font(.headline)
                                Spacer()
                                Text(entry.dateText).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(entry.items, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(AppleProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 620)
    }
}

struct ErrorText: View {
    let text: String?
    init(_ text: String?) { self.text = text }
    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
