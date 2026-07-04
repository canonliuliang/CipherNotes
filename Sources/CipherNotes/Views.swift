import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let cipherNoteUTType = UTType(filenameExtension: "ciphernote") ?? .data

private func withSecurityScopedAccess<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    return try body()
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}


private enum MotionStyle {
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.992)).combined(with: .offset(y: 8))
    }

    static func slideTransition(reduceMotion: Bool, edge: Edge = .trailing) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .move(edge: edge)),
            removal: .opacity.combined(with: .move(edge: edge == .trailing ? .leading : .trailing))
        )
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.88)
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case notes = "记事本"
    case vault = "保险柜"
    var id: String { rawValue }
}

enum NoteSort: String, CaseIterable, Identifiable {
    case updatedNewest
    case createdNewest
    case title
    case favoritesFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updatedNewest: "最近更新"
        case .createdNewest: "新建时间"
        case .title: "标题 A-Z"
        case .favoritesFirst: "收藏优先"
        }
    }
}

enum NoteFilter: String, CaseIterable, Identifiable {
    case active = "全部"
    case favorites = "收藏"
    case pinned = "置顶"
    case archived = "归档"

    var id: String { rawValue }
}

enum VaultFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case images = "图片"
    case documents = "文档"
    case media = "音视频"
    case other = "其他"

    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("hasSeenCipherNotesIntro") private var hasSeenIntro = false
    @State private var showingLegalDisclosure = false
    @State private var showingChangelog = false
    @State private var showingUserManagement = false
    @State private var showingSecurityCenter = false

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    var body: some View {
        ZStack {
            AppBackground()
            Group {
                if !hasSeenIntro {
                    IntroView {
                        hasSeenIntro = true
                    }
                } else {
                    switch store.state {
                    case .needsAdminSetup: AdminSetupView()
                    case .needsMigration: MigrationView()
                    case .locked: UnlockView()
                    case .unlocked: NotesView()
                    }
                }
            }
            .id(hasSeenIntro ? "\(store.state)" : "intro")
            .transition(MotionStyle.transition(reduceMotion: reduceMotion))
            .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: store.state)
            .padding(10)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                Spacer()
                Menu {
                    Picker("外观", selection: $appAppearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance.rawValue)
                        }
                    }
                    Toggle("减少动效", isOn: $reduceMotion)
                } label: {
                    Label("外观：\(appAppearance.label)", systemImage: "circle.lefthalf.filled")
                }
                if !store.accounts.isEmpty {
                    Button {
                        showingSecurityCenter = true
                    } label: {
                        Label("安全中心", systemImage: "shield.checkered")
                    }
                    .disabled(store.state != .unlocked)
                    Button {
                        showingUserManagement = true
                    } label: {
                        Label("用户管理", systemImage: "person.2.badge.gearshape")
                    }
                }
                Button {
                    showingChangelog = true
                } label: {
                    Label("更新日志", systemImage: "sparkles")
                }
                Button {
                    showingLegalDisclosure = true
                } label: {
                    Label("法律声明", systemImage: "doc.text.magnifyingglass")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider().opacity(0.55) }
        }
        .frame(minWidth: 860, minHeight: 620)
        .preferredColorScheme(appAppearance.colorScheme)
        .onAppear {
            DispatchQueue.main.async {
                if ProcessInfo.processInfo.environment["CIPHERNOTES_ALLOW_CAPTURE"] != "1" {
                    NSApplication.shared.windows.forEach { $0.sharingType = .none }
                }
            }
        }
        .sheet(isPresented: Binding(get: { store.recoveryCodeToShow != nil }, set: { if !$0 { store.dismissRecoveryCode() } })) {
            RecoveryCodeView(code: store.recoveryCodeToShow ?? "") {
                store.dismissRecoveryCode()
            }
        }
        .sheet(isPresented: $showingLegalDisclosure) {
            LegalDisclosureView()
        }
        .sheet(isPresented: $showingChangelog) {
            ChangelogView()
        }
        .sheet(isPresented: $showingUserManagement) {
            UserManagementView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingSecurityCenter) {
            SecurityCenterView()
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesShowUserManagement)) { _ in
            showingUserManagement = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesShowSecurityCenter)) { _ in
            showingSecurityCenter = store.state == .unlocked
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesShowChangelog)) { _ in
            showingChangelog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesShowLegalDisclosure)) { _ in
            showingLegalDisclosure = true
        }
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay {
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(colorScheme == .dark ? 0.72 : 0.64)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.mint.opacity(colorScheme == .dark ? 0.12 : 0.16))
                    .blur(radius: 90)
                    .frame(width: 360, height: 360)
                    .offset(x: -240, y: -230)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(.cyan.opacity(colorScheme == .dark ? 0.08 : 0.10))
                    .blur(radius: 100)
                    .frame(width: 420, height: 420)
                    .offset(x: 220, y: 210)
            }
            .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.04, green: 0.07, blue: 0.09),
                Color(red: 0.02, green: 0.13, blue: 0.12),
                Color(red: 0.06, green: 0.05, blue: 0.10)
            ]
        }
        return [
            Color(red: 0.92, green: 0.98, blue: 0.96),
            Color(red: 0.96, green: 0.99, blue: 0.99),
            Color(red: 0.94, green: 0.93, blue: 0.99)
        ]
    }
}

struct GlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.58), lineWidth: 1)
                    .blendMode(.plusLighter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 28, y: 16)
            .shadow(color: .white.opacity(colorScheme == .dark ? 0 : 0.55), radius: 1, y: -1)
    }
}


struct MacHoverLift: ViewModifier {
    var disabled = false
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(disabled || !hovered ? 1 : 1.012)
            .shadow(color: .black.opacity(disabled || !hovered ? 0 : 0.16), radius: 14, y: 8)
            .animation(.easeOut(duration: 0.16), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 22) -> some View {
        modifier(GlassPanel(radius: radius))
    }

    func macHoverLift(disabled: Bool = false) -> some View {
        modifier(MacHoverLift(disabled: disabled))
    }
}

struct BrandHeader: View {
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous)
                    .fill(.mint.opacity(0.18))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: compact ? 17 : 27, weight: .semibold))
                    .foregroundStyle(.mint)
            }
            .frame(width: compact ? 32 : 52, height: compact ? 32 : 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("密笺").font(compact ? .headline : .largeTitle.bold())
                Text("只属于你的本地加密笔记").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct IntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            BrandHeader()
            VStack(alignment: .leading, spacing: 16) {
                Text("欢迎使用密笺")
                    .font(.largeTitle.bold())
                Text("密笺是纯本地的加密记事本和文件保险柜。没有云端账号，没有广告，也不上传你的内容。")
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    introRow("lock.shield.fill", "本地加密", "笔记和保险柜文件只保存在这台 Mac。")
                    introRow("person.2.fill", "多账号", "账号分为管理员账号和普通账号，便于多人共用同一台 Mac。")
                    introRow("checkmark.seal.fill", "纯免费", "所有本地功能都可直接使用，没有会员、广告或购买入口。")
                    introRow("hand.raised.fill", "隐私优先", "管理员可以管理账号，但不能查看普通用户的数据。")
                }
                Text("接下来会先创建一个本机管理员密码，然后创建你的第一个账号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("开始使用") { onContinue() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .glassPanel()
            .frame(maxWidth: 620)
        }
        .padding(40)
    }

    private func introRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        GridRow {
            Image(systemName: icon)
                .foregroundStyle(.mint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct AdminSetupView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var adminPassword = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(spacing: 24) {
            BrandHeader()
            VStack(alignment: .leading, spacing: 14) {
                Text("创建管理员密码").font(.title2.bold())
                Text("管理员密码只用于允许注册新用户和升级旧保险库，不能直接查看任何用户的笔记。")
                    .font(.callout).foregroundStyle(.secondary)
                SecureField("管理员密码", text: $adminPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("再次输入管理员密码", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                ErrorText(store.errorMessage)
                Button("创建管理员密码") {
                    store.createAdminPassword(password: adminPassword, confirmation: confirmation)
                    adminPassword = ""
                    confirmation = ""
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .glassPanel()
            .frame(maxWidth: 440)
        }
        .padding(40)
    }
}

struct MigrationView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var adminPassword = ""
    @State private var adminConfirmation = ""
    @State private var username = ""
    @State private var oldPassword = ""
    @State private var enableTouchID = false

    var body: some View {
        VStack(spacing: 24) {
            BrandHeader()
            VStack(alignment: .leading, spacing: 14) {
                Text("升级旧保险库").font(.title2.bold())
                Text("这一步会保留旧笔记，同时补上新的管理员密码和用户登录体系。旧密码会成为该用户的登录密码。")
                    .font(.callout).foregroundStyle(.secondary)
                SecureField("新管理员密码", text: $adminPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("再次输入管理员密码", text: $adminConfirmation)
                    .textFieldStyle(.roundedBorder)
                Divider()
                TextField("旧版用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                SecureField("旧版主密码 / 新用户登录密码", text: $oldPassword)
                    .textFieldStyle(.roundedBorder)
                if store.biometricsAvailable {
                    Toggle("迁移后为这个账户启用 Touch ID", isOn: $enableTouchID)
                    Text("Touch ID 是这台 Mac 的系统验证，不区分密笺用户；多人共用设备时建议关闭。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ErrorText(store.errorMessage)
                Button("升级并进入") {
                    store.migrateLegacyVault(
                        adminPassword: adminPassword,
                        adminConfirmation: adminConfirmation,
                        username: username,
                        oldPassword: oldPassword,
                        enableTouchID: enableTouchID
                    )
                    adminPassword = ""
                    adminConfirmation = ""
                    oldPassword = ""
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button("跳过，清空旧数据并重新开始", role: .destructive) {
                    store.discardLegacyVaultAndStartFresh()
                }
                .buttonStyle(.borderless)
            }
            .glassPanel()
            .frame(maxWidth: 480)
        }
        .padding(40)
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case login = "登录"
    case register = "注册"
    case recover = "恢复"
    var id: String { rawValue }
}

struct UnlockView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var mode: AuthMode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var adminPassword = ""
    @State private var recoveryCode = ""
    @State private var selectedAccountID: UUID?
    @State private var enableTouchID = false
    @State private var enableTouchIDAfterPasswordLogin = false
    @State private var accountRole = AccountRole.standard
    @FocusState private var focused: Bool

    private var selectedAccount: AccountSummary? {
        guard let selectedAccountID else { return nil }
        return store.accounts.first { $0.id == selectedAccountID }
    }

    private var canSubmitLogin: Bool {
        !store.accounts.isEmpty || !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            BrandHeader()
            VStack(spacing: 14) {
                Picker("", selection: $mode) {
                    ForEach(AuthMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                ZStack {
                    if mode == .login {
                        loginForm
                            .transition(MotionStyle.slideTransition(reduceMotion: reduceMotion, edge: .trailing))
                    } else if mode == .register {
                        registerForm
                            .transition(MotionStyle.slideTransition(reduceMotion: reduceMotion, edge: .trailing))
                    } else {
                        recoveryForm
                            .transition(MotionStyle.slideTransition(reduceMotion: reduceMotion, edge: .trailing))
                    }
                }
                .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: mode)
                ErrorText(store.errorMessage)
            }
            .glassPanel()
            .frame(width: 420)
            Text("管理员管注册 · 用户管自己的加密笔记 · 无云端").font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .onAppear {
            mode = store.userCount == 0 ? .register : .login
            selectedAccountID = selectedAccountID ?? store.accounts.first?.id
            if store.userCount == 0 { accountRole = .admin }
            focused = true
        }
        .onChange(of: store.accounts) { _, accounts in
            if selectedAccountID == nil || !accounts.contains(where: { $0.id == selectedAccountID }) {
                selectedAccountID = accounts.first?.id
            }
            if accounts.isEmpty {
                mode = .register
                accountRole = .admin
            }
        }
        .onChange(of: selectedAccountID) { _, _ in
            enableTouchIDAfterPasswordLogin = false
            password = ""
        }
    }

    private var loginForm: some View {
        VStack(spacing: 14) {
            if store.accounts.isEmpty {
                TextField("用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .focused($focused)
            } else {
                Picker("选择账户", selection: Binding(
                    get: { selectedAccountID ?? store.accounts.first?.id },
                    set: { selectedAccountID = $0 }
                )) {
                    ForEach(store.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let selectedAccount {
                HStack(spacing: 8) {
                    Image(systemName: store.isTouchIDEnabled(userID: selectedAccount.id) ? "touchid" : "person.crop.circle")
                        .foregroundStyle(store.isTouchIDEnabled(userID: selectedAccount.id) ? .mint : .secondary)
                    Text(selectedAccount.displayName)
                        .font(.caption)
                    Spacer()
                    Text(store.isTouchIDEnabled(userID: selectedAccount.id) ? "Touch ID 已启用" : "密码登录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            SecureField("用户密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(unlock)
            Button("登录", action: unlock)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!canSubmitLogin)
                .keyboardShortcut(.defaultAction)
            if store.canUseTouchID(userID: selectedAccountID) {
                Button {
                    if let selectedAccountID {
                        Task { await store.unlockWithTouchID(userID: selectedAccountID) }
                    }
                } label: {
                    Label("使用 Touch ID 登录所选账户", systemImage: "touchid")
                }
                .buttonStyle(.borderless)
                Text("提示：Touch ID 验证的是这台 Mac 的指纹/生物识别，不会区分密笺里的不同用户。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.biometricsAvailable && !store.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("密码登录成功后启用 / 修复 Touch ID", isOn: $enableTouchIDAfterPasswordLogin)
                    Text("如果旧版曾经可以用 Touch ID，这里不会偷偷读取旧钥匙串；用密码进一次后会写入新版 Touch ID，之后按钮会回来。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if store.userCount == 0 {
                Text("还没有用户，请切到“注册”创建第一个用户。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var registerForm: some View {
        VStack(spacing: 14) {
            SecureField("管理员密码", text: $adminPassword)
                .textFieldStyle(.roundedBorder)
            TextField("新用户名", text: $username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .focused($focused)
            Picker("账号类型", selection: $accountRole) {
                ForEach(AccountRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.userCount == 0)
            if store.userCount == 0 {
                Text("第一个账号会作为管理员账号创建，用于管理本机账号；管理员仍不能查看其他用户数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecureField("用户密码", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("再次输入用户密码", text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .onSubmit(register)
            if store.biometricsAvailable {
                Toggle("注册后启用 Touch ID", isOn: $enableTouchID)
                Text("Touch ID 是设备级验证；如果这台 Mac 有多人录入指纹，请不要为隐私账户启用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("注册并进入", action: register)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
            Text("管理员密码只批准注册，不会解密这个用户的笔记。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recoveryForm: some View {
        VStack(spacing: 14) {
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .focused($focused)
            TextField("恢复码", text: $recoveryCode)
                .textFieldStyle(.roundedBorder)
            SecureField("新用户密码", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("再次输入新用户密码", text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .onSubmit(resetPassword)
            Button("用恢复码重设密码", action: resetPassword)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            Text("重设成功后会生成新的恢复码，旧恢复码立即失效。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func unlock() {
        let succeeded: Bool
        if let selectedAccountID, !store.accounts.isEmpty {
            succeeded = store.unlock(userID: selectedAccountID, password: password)
        } else {
            succeeded = store.unlock(username: username, password: password)
        }
        if succeeded {
            password = ""
            if enableTouchIDAfterPasswordLogin {
                store.enableTouchID()
                enableTouchIDAfterPasswordLogin = false
            }
        }
    }

    private func register() {
        store.registerUser(
            adminPassword: adminPassword,
            username: username,
            password: password,
            confirmation: confirmation,
            enableTouchID: enableTouchID,
            role: accountRole
        )
        if store.state == .unlocked {
            adminPassword = ""
            password = ""
            confirmation = ""
        }
    }

    private func resetPassword() {
        store.resetPasswordWithRecoveryCode(
            username: username,
            recoveryCode: recoveryCode,
            newPassword: password,
            confirmation: confirmation
        )
        if store.state == .unlocked {
            recoveryCode = ""
            password = ""
            confirmation = ""
        }
    }
}

struct NotesView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("noteSort") private var noteSortRawValue = NoteSort.updatedNewest.rawValue
    @AppStorage("noteFilter") private var noteFilterRawValue = NoteFilter.active.rawValue
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var selection: UUID?
    @State private var query = ""
    @State private var showingExportShare = false
    @State private var showingImportShare = false
    @State private var sharePassword = ""
    @State private var importPassword = ""
    @State private var pendingImportData: Data?
    @State private var workspaceMode: WorkspaceMode = .notes

    private var filteredNotes: [Note] {
        let baseNotes: [Note]
        switch NoteFilter(rawValue: noteFilterRawValue) ?? .active {
        case .active:
            baseNotes = store.notes.filter { !$0.isArchived }
        case .favorites:
            baseNotes = store.notes.filter { $0.isFavorite && !$0.isArchived }
        case .pinned:
            baseNotes = store.notes.filter { $0.isPinned && !$0.isArchived }
        case .archived:
            baseNotes = store.notes.filter(\.isArchived)
        }

        let notes: [Note]
        if query.isEmpty {
            notes = baseNotes
        } else {
            notes = baseNotes.filter { note in
                note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        switch NoteSort(rawValue: noteSortRawValue) ?? .updatedNewest {
        case .updatedNewest:
            return notes.sorted(by: noteSort)
        case .createdNewest:
            return notes.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
        case .title:
            return notes.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return (lhs.title.isEmpty ? "无标题" : lhs.title).localizedCaseInsensitiveCompare(rhs.title.isEmpty ? "无标题" : rhs.title) == .orderedAscending
            }
        case .favoritesFirst:
            return notes.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private var activeNotesCount: Int { store.notes.filter { !$0.isArchived }.count }
    private var archivedNotesCount: Int { store.notes.filter(\.isArchived).count }

    private func noteSort(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        return lhs.updatedAt > rhs.updatedAt
    }
    private var selectedNote: Note? {
        guard let selection else { return nil }
        return store.notes.first { $0.id == selection }
    }

    private var storeErrorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isPresented in
                if !isPresented { store.errorMessage = nil }
            }
        )
    }

    private var currentAccountBadgeText: String {
        "\(store.currentAccountRole.shortLabel)账号 · 纯免费"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("区域", selection: $workspaceMode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ZStack {
                if workspaceMode == .notes {
                    notesBody
                        .transition(MotionStyle.slideTransition(reduceMotion: reduceMotion, edge: .leading))
                } else {
                    VaultView()
                        .environmentObject(store)
                        .transition(MotionStyle.slideTransition(reduceMotion: reduceMotion, edge: .trailing))
                }
            }
            .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: workspaceMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesAddAttachments)) { _ in
            workspaceMode = .vault
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cipherNotesOpenVaultImporter, object: nil)
            }
        }
    }

    private var notesBody: some View {
        AnyView(NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    BrandHeader(compact: true)
                    if let username = store.signedInUsername {
                        Label(username, systemImage: "person.crop.circle.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Label(currentAccountBadgeText, systemImage: "crown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.currentAccountAdvancedDataProtectionEnabled {
                        Label("高级数据保护已开启", systemImage: "shield.lefthalf.filled")
                            .font(.caption)
                            .foregroundStyle(.mint)
                    }
                    Picker("筛选", selection: $noteFilterRawValue) {
                        ForEach(NoteFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                List(selection: $selection) {
                    ForEach(filteredNotes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                if note.isPinned {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.orange)
                                }
                                if note.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                                Text(note.title.isEmpty ? "无标题" : note.title)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            Text(notePreviewText(for: note)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if !note.tags.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption2)
                                            .foregroundStyle(.mint)
                                    }
                                }
                            }
                            Text(note.updatedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .tag(note.id)
                        .contextMenu {
                            Button(note.isPinned ? "取消置顶" : "置顶") { store.togglePinned(noteID: note.id) }
                            Button(note.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(noteID: note.id) }
                            Button(note.isArchived ? "移回笔记列表" : "归档") { store.toggleArchived(noteID: note.id) }
                            Divider()
                            Button("复制笔记内容") { copyNote(note) }
                            Button("复制为新笔记") {
                                if let id = store.duplicateNote(id: note.id) { selection = id }
                            }
                            Divider()
                            Button("导出为 Markdown…") { exportPlainNote(note, fileExtension: "md") }
                            Button("导出为 TXT…") { exportPlainNote(note, fileExtension: "txt") }
                            Button("导出共享文件") {
                                selection = note.id
                                showingExportShare = true
                            }
                            Button("删除", role: .destructive) { delete(note.id) }
                        }
                    }
                }
                .searchable(text: $query, prompt: "搜索已解锁的笔记")
                HStack {
                    Button { selection = store.addNote() } label: { Label("新笔记", systemImage: "square.and.pencil") }
                    Spacer()
                    Text("\(activeNotesCount) 条 · 归档 \(archivedNotesCount)").foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
            .background(.thinMaterial)
        } detail: {
            if let selection, store.notes.contains(where: { $0.id == selection }) {
                NoteEditor(noteID: selection)
            } else {
                ContentUnavailableView("选择一条笔记", systemImage: "note.text", description: Text("或创建一条新的加密笔记"))
            }
        })
        .toolbar(content: notesToolbar)
        .onAppear(perform: ensureSelection)
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesNewNote)) { _ in addNewNoteFromCommand() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesDuplicateNote)) { _ in duplicateSelectedNote() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesTogglePinned)) { _ in togglePinnedSelectedNote() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesToggleFavorite)) { _ in toggleFavoriteSelectedNote() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesToggleArchived)) { _ in toggleArchivedSelectedNote() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesExportMarkdown)) { _ in
            exportSelectedPlainNote(fileExtension: "md")
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesExportText)) { _ in
            exportSelectedPlainNote(fileExtension: "txt")
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesDeleteNote)) { _ in deleteSelectedNoteFromCommand() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesCopyNote)) { _ in copySelectedNote() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesExportNote)) { _ in showShareExportForSelectedNote() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesImportNote)) { _ in chooseSharedFile() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesBackupVault)) { _ in backupVault() }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesRestoreVault)) { _ in restoreVault() }
        .alert("密笺", isPresented: storeErrorPresented, actions: errorAlertActions, message: errorAlertMessage)
        .sheet(isPresented: $showingExportShare, content: exportShareSheet)
        .sheet(isPresented: $showingImportShare, content: importShareSheet)
    }

    private func delete(_ id: UUID) {
        store.deleteNote(id: id)
        if selection == id { selection = store.notes.first?.id }
    }

    private func deleteSelectedNoteFromCommand() {
        guard let selection else { return }
        delete(selection)
    }

    @ToolbarContentBuilder
    private func notesToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                notesToolbarMenu
            } label: {
                Image(systemName: "gearshape")
            }
            Button {
                store.lock()
            } label: {
                Label("锁定", systemImage: "lock.fill")
            }
            .keyboardShortcut("l", modifiers: .command)
        }
    }

    @ViewBuilder
    private var notesToolbarMenu: some View {
        Picker("自动锁定", selection: $store.autoLockMinutes) {
            Text("1 分钟").tag(1)
            Text("5 分钟").tag(5)
            Text("15 分钟").tag(15)
            Text("30 分钟").tag(30)
        }
        Divider()
        Picker("笔记排序", selection: $noteSortRawValue) {
            ForEach(NoteSort.allCases) { sort in
                Text(sort.label).tag(sort.rawValue)
            }
        }
        Picker("笔记筛选", selection: $noteFilterRawValue) {
            ForEach(NoteFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter.rawValue)
            }
        }
        Divider()
        Button("置顶 / 取消置顶") { togglePinnedSelectedNote() }
            .disabled(selectedNote == nil)
        Button("收藏 / 取消收藏") { toggleFavoriteSelectedNote() }
            .disabled(selectedNote == nil)
        Button("归档 / 移回") { toggleArchivedSelectedNote() }
            .disabled(selectedNote == nil)
        Divider()
        Button("复制所选笔记内容") { copySelectedNote() }
            .disabled(selectedNote == nil)
        Button("复制所选笔记为新笔记") { duplicateSelectedNote() }
            .disabled(selectedNote == nil)
        Divider()
        Button("导出所选笔记为 Markdown…") { exportSelectedPlainNote(fileExtension: "md") }
            .disabled(selectedNote == nil)
        Button("导出所选笔记为 TXT…") { exportSelectedPlainNote(fileExtension: "txt") }
            .disabled(selectedNote == nil)
        Button("导出所选笔记为共享文件") { showingExportShare = true }
            .disabled(selectedNote == nil)
        Button("导入共享文件") { chooseSharedFile() }
        Divider()
        if store.biometricsAvailable {
            Button("为当前账户启用 Touch ID") { store.enableTouchID() }
            Button("关闭当前账户 Touch ID") { store.disableTouchID() }
        }
        Button(store.currentAccountAdvancedDataProtectionEnabled ? "关闭高级数据保护" : "开启高级数据保护") {
            store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
        }
        Button("生成新的恢复码") {
            store.rotateRecoveryCode()
        }
    }

    private func exportShareSheet() -> some View {
        ShareExportView(noteTitle: selectedNote?.title ?? "共享笔记", password: $sharePassword) {
            sharePassword = ""
            showingExportShare = false
        } onExport: {
            exportSelectedNote()
        }
    }

    private func importShareSheet() -> some View {
        ShareImportView(password: $importPassword) {
            importPassword = ""
            pendingImportData = nil
            showingImportShare = false
        } onImport: {
            importPendingSharedNote()
        }
    }

    private func errorAlertActions() -> some View {
        Button("好") { store.errorMessage = nil }
    }

    private func errorAlertMessage() -> some View {
        Text(store.errorMessage ?? "")
    }

    private func addNewNoteFromCommand() {
        guard store.state == .unlocked else { return }
        selection = store.addNote()
    }

    private func ensureSelection() {
        guard selection == nil else { return }
        selection = store.notes.first?.id
    }

    private func duplicateSelectedNote() {
        guard let selection, let id = store.duplicateNote(id: selection) else { return }
        self.selection = id
    }

    private func togglePinnedSelectedNote() {
        guard let selection else { return }
        store.togglePinned(noteID: selection)
    }

    private func toggleFavoriteSelectedNote() {
        guard let selection else { return }
        store.toggleFavorite(noteID: selection)
    }

    private func toggleArchivedSelectedNote() {
        guard let selection else { return }
        store.toggleArchived(noteID: selection)
        if selectedNote?.isArchived == true && (NoteFilter(rawValue: noteFilterRawValue) ?? .active) != .archived {
            self.selection = filteredNotes.first?.id
        }
    }

    private func copySelectedNote() {
        guard let selectedNote else { return }
        copyNote(selectedNote)
    }

    private func copyNote(_ note: Note) {
        let title = note.title.isEmpty ? "无标题" : note.title
        let text = note.body.isEmpty ? title : "\(title)\n\n\(note.body)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.errorMessage = "笔记内容已复制到剪贴板"
    }

    private func showShareExportForSelectedNote() {
        guard selectedNote != nil else { return }
        showingExportShare = true
    }

    private func notePreviewText(for note: Note) -> String {
        if store.currentAccountAdvancedDataProtectionEnabled {
            return note.body.isEmpty ? "高级保护：空笔记" : "高级保护已隐藏正文预览"
        }
        return note.body.isEmpty ? "空笔记" : note.body
    }

    private func exportSelectedNote() {
        guard let selection, let data = store.exportSharedNote(id: selection, sharePassword: sharePassword) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [cipherNoteUTType]
        panel.nameFieldStringValue = "\(safeFileName(selectedNote?.title ?? "共享笔记")).ciphernote"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try withSecurityScopedAccess(url) {
                try data.write(to: url, options: [.atomic])
            }
            sharePassword = ""
            showingExportShare = false
            store.errorMessage = "共享文件已导出"
        } catch {
            store.errorMessage = "写入共享文件失败：\(error.localizedDescription)"
        }
    }

    private func exportPlainNote(_ note: Note, fileExtension: String) {
        let panel = NSSavePanel()
        let title = note.title.isEmpty ? "无标题" : note.title
        panel.allowedContentTypes = fileExtension == "md" ? [UTType(filenameExtension: "md") ?? .plainText] : [.plainText]
        panel.nameFieldStringValue = "\(safeFileName(title)).\(fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let tags = note.tags.isEmpty ? "" : "\n\n标签：\(note.tags.map { "#\($0)" }.joined(separator: " "))"
        let content: String
        if fileExtension == "md" {
            content = "# \(title)\n\n\(note.body)\(tags)\n"
        } else {
            content = "\(title)\n\n\(note.body)\(tags)\n"
        }
        do {
            try withSecurityScopedAccess(url) {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
            store.errorMessage = fileExtension == "md" ? "Markdown 已导出" : "TXT 已导出"
        } catch {
            store.errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportSelectedPlainNote(fileExtension: String) {
        guard let selectedNote else { return }
        exportPlainNote(selectedNote, fileExtension: fileExtension)
    }

    private func backupVault() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "密笺备份"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.backupVault(to: url)
    }

    private func restoreVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择备份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "从备份还原保险库？"
        alert.informativeText = "这将用备份数据覆盖当前保险库，当前未备份的笔记和保险柜文件将永久丢失。确定要继续吗？"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "还原")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.restoreVault(from: url)
    }


    private func chooseSharedFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [cipherNoteUTType, .json, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImportData = try withSecurityScopedAccess(url) {
                try Data(contentsOf: url)
            }
            showingImportShare = true
        } catch {
            store.errorMessage = "读取共享文件失败：\(error.localizedDescription)"
        }
    }

    private func importPendingSharedNote() {
        guard let pendingImportData else { return }
        if let id = store.importSharedNote(data: pendingImportData, sharePassword: importPassword) {
            selection = id
            importPassword = ""
            self.pendingImportData = nil
            showingImportShare = false
        }
    }

    private func safeFileName(_ value: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value.components(separatedBy: unsafe).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "共享笔记" : cleaned
    }
}

struct NoteEditor: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("markdownPreview") private var markdownPreview = false
    let noteID: UUID
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var tagsText = ""
    @State private var loadedNoteID: UUID?
    @State private var saveTask: Task<Void, Never>?
    @State private var savePending = false

    private var note: Note? { store.notes.first { $0.id == noteID } }

    private var characterCount: Int {
        draftBody.count
    }

    private var lineCount: Int {
        max(1, draftBody.components(separatedBy: .newlines).count)
    }

    private var wordCount: Int {
        draftBody.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var readingMinutes: Int {
        max(1, Int(ceil(Double(max(wordCount, characterCount / 2)) / 350.0)))
    }

    private var markdownAttributedString: AttributedString {
        (try? AttributedString(markdown: draftBody.isEmpty ? "空笔记" : draftBody)) ?? AttributedString(draftBody.isEmpty ? "空笔记" : draftBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("标题", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                if let note {
                    Button {
                        store.togglePinned(noteID: note.id)
                    } label: {
                        Label(note.isPinned ? "取消置顶" : "置顶", systemImage: note.isPinned ? "pin.fill" : "pin")
                    }
                    .labelStyle(.iconOnly)
                    Button {
                        store.toggleFavorite(noteID: note.id)
                    } label: {
                        Label(note.isFavorite ? "取消收藏" : "收藏", systemImage: note.isFavorite ? "star.fill" : "star")
                    }
                    .labelStyle(.iconOnly)
                    Button {
                        markdownPreview.toggle()
                    } label: {
                        Label(markdownPreview ? "编辑" : "Markdown 预览", systemImage: markdownPreview ? "pencil" : "doc.richtext")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 28).padding(.top, 24)
            if let note {
                HStack(spacing: 10) {
                    Text("最后更新 \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("·")
                    Text("\(characterCount) 字符")
                    Text("·")
                    Text("\(wordCount) 词")
                    Text("·")
                    Text("\(lineCount) 行")
                    Text("·")
                    Text("约 \(readingMinutes) 分钟")
                    Text("·")
                    Label("自动保存", systemImage: "checkmark.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .padding(.top, 6)
            }
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                TextField("标签，用逗号分隔，例如 工作, 灵感, 私密", text: $tagsText)
                    .textFieldStyle(.plain)
                    .onSubmit(saveNow)
            }
            .font(.caption)
            .padding(.horizontal, 28)
            .padding(.top, 10)
            Divider().padding(.top, 16)
            if markdownPreview {
                ScrollView {
                    Text(markdownAttributedString)
                        .font(.system(size: 16))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                .transition(MotionStyle.transition(reduceMotion: false))
            } else {
                TextEditor(text: $draftBody)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(20)
                    .transition(MotionStyle.transition(reduceMotion: false))
            }
        }
        .background(.regularMaterial)
        .onAppear(perform: loadDraft)
        .onChange(of: noteID) { _, _ in loadDraft() }
        .onChange(of: draftTitle) { _, _ in scheduleSave() }
        .onChange(of: draftBody) { _, _ in scheduleSave() }
        .onChange(of: tagsText) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            saveNow()
        }
    }

    private func loadDraft() {
        guard loadedNoteID != noteID else { return }
        saveTask?.cancel()
        draftTitle = note?.title ?? ""
        draftBody = note?.body ?? ""
        tagsText = note?.tags.joined(separator: ", ") ?? ""
        loadedNoteID = noteID
        savePending = false
    }

    private func scheduleSave() {
        guard loadedNoteID == noteID else { return }
        saveTask?.cancel()
        savePending = true
        let title = draftTitle
        let body = draftBody
        let tags = parsedTags
        let id = noteID
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            if let current = store.notes.first(where: { $0.id == id }), current.title != title || current.body != body {
                store.updateNote(id: id, title: title, body: body)
            }
            if let current = store.notes.first(where: { $0.id == id }), current.tags != tags {
                store.updateTags(noteID: id, tags: tags)
            }
            savePending = false
        }
    }

    private func saveNow() {
        guard loadedNoteID == noteID else { return }
        if let current = store.notes.first(where: { $0.id == noteID }), current.title != draftTitle || current.body != draftBody {
            store.updateNote(id: noteID, title: draftTitle, body: draftBody)
        }
        if let current = store.notes.first(where: { $0.id == noteID }), current.tags != parsedTags {
            store.updateTags(noteID: noteID, tags: parsedTags)
        }
        savePending = false
    }

    private var parsedTags: [String] {
        tagsText
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct VaultView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var query = ""
    @State private var filter: VaultFilter = .all

    private var filteredItems: [VaultAttachment] {
        let scoped = store.vaultItems.filter { item in
            switch filter {
            case .all:
                true
            case .images:
                item.contentType?.hasPrefix("image/") == true
            case .documents:
                item.contentType?.hasPrefix("text/") == true
                || item.contentType == "application/pdf"
                || item.contentType?.contains("word") == true
                || item.contentType?.contains("spreadsheet") == true
            case .media:
                item.contentType?.hasPrefix("audio/") == true || item.contentType?.hasPrefix("video/") == true
            case .other:
                !(item.contentType?.hasPrefix("image/") == true)
                && !(item.contentType?.hasPrefix("text/") == true)
                && item.contentType != "application/pdf"
                && !(item.contentType?.hasPrefix("audio/") == true)
                && !(item.contentType?.hasPrefix("video/") == true)
            }
        }
        let items = scoped.sorted { $0.createdAt > $1.createdAt }
        guard !query.isEmpty else { return items }
        return items.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
    }

    private var totalByteCount: Int {
        store.vaultItems.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("保险柜", systemImage: "lock.rectangle.stack.fill")
                        .font(.title2.bold())
                    Text("照片和文件独立保存在保险柜里。移入成功后，原文件会从原位置删除。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    chooseVaultFiles()
                } label: {
                    Label("移入照片或文件", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("搜索保险柜文件", text: $query)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("文件类型", selection: $filter) {
                    ForEach(VaultFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
                Text("\(store.vaultItems.count) 个文件 · \(ByteCountFormatter.string(fromByteCount: Int64(totalByteCount), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    store.vaultItems.isEmpty ? "保险柜是空的" : "没有匹配的文件",
                    systemImage: "lock.rectangle",
                    description: Text("点“移入照片或文件”，应用会先加密保存，再删除原文件。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        ForEach(filteredItems) { item in
                            VaultItemCard(item: item)
                                .environmentObject(store)
                                .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                                .macHoverLift(disabled: reduceMotion)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: filteredItems.map(\.id))
            }
        }
        .padding(24)
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesOpenVaultImporter)) { _ in
            chooseVaultFiles()
        }
        .alert("密笺", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func chooseVaultFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "移入保险柜后，原照片/原文件会从原位置删除"
        panel.prompt = "加密并删除原文件"
        guard panel.runModal() == .OK else { return }
        store.importFilesToVault(urls: panel.urls, deleteOriginals: true)
    }
}

struct VaultItemCard: View {
    @EnvironmentObject private var store: VaultStore
    let item: VaultAttachment
    @State private var preview: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 118)
            Text(item.fileName)
                .font(.headline)
                .lineLimit(2)
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("导出") { exportItem() }
                Button("复制文件名") { copyFileName() }
                Spacer()
                Button("删除", role: .destructive) { store.deleteVaultItem(itemID: item.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: item.id) {
            if isImage { preview = store.previewVaultImage(itemID: item.id) }
        }
    }

    private var isImage: Bool { item.contentType?.hasPrefix("image/") == true }

    private var systemImage: String {
        if item.contentType == "application/pdf" { return "doc.richtext" }
        if item.contentType?.hasPrefix("audio/") == true { return "waveform" }
        if item.contentType?.hasPrefix("video/") == true { return "film" }
        if item.contentType?.hasPrefix("text/") == true { return "doc.text" }
        return "doc.fill"
    }

    private func exportItem() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportVaultItem(itemID: item.id, to: url)
    }

    private func copyFileName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.fileName, forType: .string)
        store.errorMessage = "文件名已复制"
    }
}

struct ShareExportView: View {
    let noteTitle: String
    @Binding var password: String
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("导出共享文件", systemImage: "square.and.arrow.up")
                .font(.title2.bold())
            Text("将“\(noteTitle.isEmpty ? "无标题" : noteTitle)”导出为加密的 .ciphernote 文件。把文件和共享密码分别发给另一个本机用户。")
                .foregroundStyle(.secondary)
            SecureField("共享密码", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("共享密码可以留空，也可以很短；越简单越容易被猜到。应用不会保存这个密码。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("选择保存位置", action: onExport)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct ShareImportView: View {
    @Binding var password: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("导入共享文件", systemImage: "tray.and.arrow.down.fill")
                .font(.title2.bold())
            Text("输入发送者告诉你的共享密码。导入后，这条笔记会复制到当前登录用户自己的加密保险库里。")
                .foregroundStyle(.secondary)
            SecureField("共享密码", text: $password)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("导入", action: onImport)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

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
                    .buttonStyle(.borderedProminent)
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
                    Text("应用不上传笔记、不提供云端恢复，也不保存明文用户密码、恢复码或共享密码。为方便登录页选择账户，账户显示名会保存在本机保险库文件中。忘记用户密码且没有恢复码时，相关笔记可能无法恢复。")
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 430)
    }
}

struct SecurityCenterView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    private var storeErrorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isPresented in
                if !isPresented { store.errorMessage = nil }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全中心", systemImage: "shield.checkered")
                        .font(.title2.bold())
                    Text("集中查看当前账号、本地保险库和恢复能力。所有操作都只在这台 Mac 上完成。")
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
                        securityMetric("当前账号", store.signedInUsername ?? "未登录", "person.crop.circle.fill", .mint)
                        securityMetric("账号角色", store.currentAccountRole.shortLabel, "person.badge.key.fill", .blue)
                        securityMetric("笔记", "\(store.notes.count) 条", "note.text", .indigo)
                        securityMetric("保险柜", "\(store.vaultItems.count) 个文件", "lock.rectangle.stack.fill", .teal)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("保护状态", systemImage: "checkmark.shield.fill")
                        securityRow(
                            title: "高级数据保护",
                            value: store.currentAccountAdvancedDataProtectionEnabled ? "已开启" : "未开启",
                            systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield",
                            tint: store.currentAccountAdvancedDataProtectionEnabled ? .mint : .secondary
                        )
                        securityRow(
                            title: "Touch ID",
                            value: store.currentAccountTouchIDEnabled ? "当前账号已启用" : (store.biometricsAvailable ? "当前账号未启用" : "这台 Mac 暂不可用"),
                            systemImage: "touchid",
                            tint: store.currentAccountTouchIDEnabled ? .mint : .secondary
                        )
                        securityRow(
                            title: "自动锁定",
                            value: "\(store.autoLockMinutes) 分钟",
                            systemImage: "timer",
                            tint: .secondary
                        )
                        Picker("自动锁定", selection: $store.autoLockMinutes) {
                            Text("1 分钟").tag(1)
                            Text("5 分钟").tag(5)
                            Text("15 分钟").tag(15)
                            Text("30 分钟").tag(30)
                        }
                        .pickerStyle(.segmented)
                    }
                    .securitySection()

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("快捷操作", systemImage: "wand.and.stars")
                        HStack(spacing: 10) {
                            Button {
                                store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
                            } label: {
                                Label(store.currentAccountAdvancedDataProtectionEnabled ? "关闭高级保护" : "开启高级保护", systemImage: "shield.lefthalf.filled")
                            }
                            if store.biometricsAvailable {
                                Button {
                                    if store.currentAccountTouchIDEnabled {
                                        store.disableTouchID()
                                    } else {
                                        store.enableTouchID()
                                    }
                                } label: {
                                    Label(store.currentAccountTouchIDEnabled ? "关闭 Touch ID" : "启用 Touch ID", systemImage: "touchid")
                                }
                            }
                            Button {
                                store.rotateRecoveryCode()
                            } label: {
                                Label("生成恢复码", systemImage: "key.fill")
                            }
                        }
                        .buttonStyle(.bordered)
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
                        HStack(spacing: 10) {
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
                        .buttonStyle(.bordered)
                    }
                    .securitySection()
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
        .frame(width: 680, height: 660)
        .alert("密笺", isPresented: storeErrorPresented) {
            Button("好") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
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

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func securityRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(tint)
            Text(title)
                .font(.callout.weight(.medium))
            Spacer(minLength: 16)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
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
        store.restoreVault(from: url)
    }

    private func copyVaultPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.vaultStoragePath, forType: .string)
        store.errorMessage = "本地数据位置已复制"
    }
}

private extension View {
    func securitySection() -> some View {
        padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct UserManagementView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenCipherNotesIntro") private var hasSeenIntro = false
    @State private var adminPassword = ""
    @State private var newAdminPassword = ""
    @State private var newAdminConfirmation = ""
    @State private var pendingDelete: AccountSummary?
    @State private var confirmingFullReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("用户管理", systemImage: "person.2.badge.gearshape")
                .font(.title2.bold())
            Text("管理员可以删除任何用户，但不能查看用户笔记。删除会直接销毁该用户的加密笔记、恢复码包装密钥和 Touch ID 快捷解锁项。")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("管理员密码（如果管理员密码为空，可直接留空）", text: $adminPassword)
                .textFieldStyle(.roundedBorder)
            if confirmingFullReset {
                VStack(alignment: .leading, spacing: 12) {
                    Label("确认清空这台 Mac 上的所有密笺数据？", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("继续后会删除所有用户、笔记、保险柜文件、恢复码包装密钥和 Touch ID 快捷解锁项。这个操作不可恢复。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("取消") {
                            confirmingFullReset = false
                        }
                        Spacer()
                        Button("清空全部数据并重新开始", role: .destructive) {
                            store.eraseAllDataAndStartFresh(adminPassword: adminPassword)
                            if store.state == .needsAdminSetup {
                                hasSeenIntro = false
                                adminPassword = ""
                                newAdminPassword = ""
                                newAdminConfirmation = ""
                                confirmingFullReset = false
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("修改管理员密码")
                    .font(.headline)
                SecureField("新管理员密码", text: $newAdminPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("再次输入新管理员密码", text: $newAdminConfirmation)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("更新管理员密码") {
                        store.changeAdminPassword(
                            currentPassword: adminPassword,
                            newPassword: newAdminPassword,
                            confirmation: newAdminConfirmation
                        )
                        if store.errorMessage == "管理员密码已更新" {
                            adminPassword = ""
                            newAdminPassword = ""
                            newAdminConfirmation = ""
                        }
                    }
                    .disabled(newAdminPassword != newAdminConfirmation)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Divider()
            if store.accounts.isEmpty {
                ContentUnavailableView("暂无用户", systemImage: "person.crop.circle.badge.questionmark")
            } else if let pendingDelete {
                VStack(alignment: .leading, spacing: 14) {
                    Label("确认销毁“\(pendingDelete.displayName)”？", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("管理员不能查看这个用户的笔记。继续后，应用会移除该用户的加密笔记、恢复码包装密钥和 Touch ID 快捷解锁项，数据不可恢复。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("取消") {
                            self.pendingDelete = nil
                        }
                        Spacer()
                        Button("确认删除并销毁数据", role: .destructive) {
                            store.deleteUser(userID: pendingDelete.id, adminPassword: adminPassword)
                            self.pendingDelete = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                List {
                    ForEach(store.accounts, id: \.id) { account in
                        accountRow(account)
                    }
                }
                .frame(minHeight: 180)
            }
            ErrorText(store.errorMessage)
            HStack {
                Button("清空全部数据", role: .destructive) {
                    confirmingFullReset = true
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 620)
    }

    private func accountRow(_ account: AccountSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.headline)
                Text("删除后数据不可恢复")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(account.role.shortLabel)账号", systemImage: "person.badge.key")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(
                    store.canUseTouchID(userID: account.id) ? "Touch ID 已启用" : "Touch ID 未启用",
                    systemImage: "touchid"
                )
                .font(.caption2)
                .foregroundStyle(store.canUseTouchID(userID: account.id) ? .mint : .secondary)
                Label(
                    account.advancedDataProtectionEnabled ? "高级数据保护已开启" : "高级数据保护未开启",
                    systemImage: account.advancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield"
                )
                .font(.caption2)
                .foregroundStyle(account.advancedDataProtectionEnabled ? .mint : .secondary)
            }
            Spacer()
            if store.canUseTouchID(userID: account.id) {
                Button("关闭 Touch ID") {
                    store.disableTouchID(userID: account.id)
                }
                .buttonStyle(.borderless)
            }
            Button("删除", role: .destructive) {
                pendingDelete = account
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    private let entries: [UpdateLogEntry] = [
        UpdateLogEntry(
            id: "0.11.0",
            version: "0.11.0",
            title: "纯免费版本与管理员安全补全",
            dateText: "2026-06-28",
            items: [
                "移除会员、购买、恢复购买和所有付费门槛，现有本地功能全部免费可用。",
                "注册页不再出现会员等级；高级数据保护和恢复码重生成变为普通安全功能。",
                "用户管理新增修改管理员密码和清空全部数据并重新开始，管理员/普通用户职责更完整。",
                "新增一键 release 打包脚本，自动测试、构建并更新 app、pkg、zip、说明文档和图标。",
                "重绘应用图标，改为现代简约的蓝青 Fluent 风格。",
                "新增安全中心，集中查看账号保护状态、自动锁定、Touch ID、恢复码、备份还原和本地数据位置。",
                "保险柜改为分片加密存储，超大文件会后台导入并支持流式导出，不再一次性读入内存。",
                "优化保险柜大图预览、文件权限访问和发布打包流程，减少卡顿与权限噪音。",
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
            title: "账号角色与安全能力整理",
            dateText: "2026-06-27",
            items: [
                "首次打开新增应用简介，引导用户理解本地加密、多账号和隐私边界。",
                "创建账号时可选择管理员账号或普通账号。",
                "管理员负责批准注册、管理用户和备份还原，但仍不能查看用户笔记。",
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
                "用户管理会显示每个账号的高级数据保护状态，管理员仍不能查看用户数据。"
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
            title: "Touch ID 迁移、登录细节与 macOS 质感修补",
            dateText: "2026-06-27",
            items: [
                "旧版 Touch ID 用户可在密码登录成功后直接启用 / 修复新版 Touch ID，不再像功能凭空消失。",
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
                "Touch ID 状态改为保险库元数据，登录页和用户管理不再为了显示按钮读取钥匙串。",
                "新 Touch ID 使用 app.ciphernotes.touchid-v2，旧 Touch ID 用户需用密码登录后重新启用一次。",
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
            title: "窗口、Touch ID、安全提示与菜单栏增强",
            dateText: "2026-06-27",
            items: [
                "修复底部按钮可能遮挡内容的窗口显示问题，并恢复标准窗口标题栏。",
                "明确 Touch ID 是 macOS 设备级验证；每个账户独立保存快捷解锁密钥，可单独关闭。",
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
                "用户管理改为窗口内二次确认，删除流程更清楚、更可靠。",
                "新增外观选择：跟随系统、浅色、深色。"
            ]
        ),
        UpdateLogEntry(
            id: "0.6.0",
            version: "0.6.0",
            title: "无账号密码限制与管理员销毁用户",
            dateText: "2026-06-27",
            items: [
                "取消用户名格式、用户名长度和密码长度限制，空用户名会显示为“未命名账户”。",
                "管理员可在用户管理中删除任意用户；删除只销毁数据，不能查看用户笔记。",
                "优化按钮禁用、提示文案和误删确认，让流程更贴近真实使用。"
            ]
        ),
        UpdateLogEntry(
            id: "0.5.0",
            version: "0.5.0",
            title: "账户选择、Touch ID 与更新日志",
            dateText: "2026-06-27",
            items: [
                "注册和旧数据迁移时可选择为账户启用 Touch ID。",
                "登录页改为先选择账户，再用密码或 Touch ID 登录。",
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
            Label("更新日志", systemImage: "sparkles")
                .font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(entries) { entry in
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 520)
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
