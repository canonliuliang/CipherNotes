import AppKit
import AVKit
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private let cipherNoteUTType = UTType(filenameExtension: "ciphernote") ?? .data

private func withSecurityScopedAccess<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    return try body()
}

@MainActor
private func requestDangerAuthorization(title: String, message: String, confirmationPrompt: String) -> (password: String, confirmation: String)? {
    let passwordField = NSSecureTextField()
    passwordField.placeholderString = "当前账户密码"
    passwordField.frame.size.width = 320

    let confirmationField = NSTextField()
    confirmationField.placeholderString = confirmationPrompt
    confirmationField.frame.size.width = 320

    let stack = NSStackView(views: [passwordField, confirmationField])
    stack.orientation = .vertical
    stack.spacing = 8
    stack.frame.size = NSSize(width: 320, height: 58)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.accessoryView = stack
    alert.addButton(withTitle: "继续")
    alert.addButton(withTitle: "取消")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return (passwordField.stringValue, confirmationField.stringValue)
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("hasSeenCipherNotesIntro") private var hasSeenIntro = false
    @State private var showingLegalDisclosure = false
    @State private var showingChangelog = false
    @State private var showingUserManagement = false
    @State private var showingSecurityCenter = false
    @State private var privacyShieldActive = false

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
                    case .needsAdminSetup: UnlockView()
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
            if privacyShieldActive && store.state == .unlocked && store.currentAccountAdvancedDataProtectionEnabled {
                PrivacyShieldOverlay {
                    privacyShieldActive = false
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .safeAreaInset(edge: .bottom) {
            rootFooter
        }
        .safeAreaInset(edge: .top, spacing: 0) {
        }
        .frame(minWidth: 860, minHeight: 620)
        .preferredColorScheme(appAppearance.colorScheme)
        .onAppear {
            DispatchQueue.main.async {
                NSApplication.shared.windows.forEach { $0.sharingType = .none }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard store.state == .unlocked, store.currentAccountAdvancedDataProtectionEnabled else { return }
            if newPhase != .active {
                privacyShieldActive = true
                store.clearSensitivePreviewCaches()
            }
        }
        .onChange(of: store.currentAccountAdvancedDataProtectionEnabled) { _, enabled in
            if !enabled { privacyShieldActive = false }
        }
        .sheet(isPresented: Binding(get: { store.recoveryCodeToShow != nil }, set: { if !$0 { store.dismissRecoveryCode() } })) {
            RecoveryCodeView(code: store.recoveryCodeToShow ?? "") {
                store.dismissRecoveryCode()
            }
            .environmentObject(store)
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

    private var rootFooter: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
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
                    Label("账户与安全", systemImage: "person.2.badge.gearshape")
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
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
    }
}

private struct PrivacyShieldOverlay: View {
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.mint)
                Text("最高保护遮罩已开启")
                    .font(.title3.weight(.semibold))
                Text("窗口离开活动状态后，密笺会遮住内容并清理预览缓存，减少屏幕暴露和临时查看残留。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button {
                    onReveal()
                } label: {
                    Label("恢复查看", systemImage: "eye.fill")
                }
                .buttonStyle(ClearButtonStyle(prominence: .primary))
            }
            .padding(30)
            .nativeGlassSurface(radius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.mint.opacity(0.30), lineWidth: 1)
            }
        }
    }
}

struct AppBackground: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .ignoresSafeArea()
    }
}

struct GlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 18
    var padding: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background(.regularMaterial, in: shape)
            .overlay(alignment: .top) {
                shape
                    .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.58), lineWidth: 1)
                    .blendMode(.plusLighter)
            }
            .overlay {
                shape
                    .stroke(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 28, y: 16)
            .shadow(color: .white.opacity(colorScheme == .dark ? 0 : 0.55), radius: 1, y: -1)
    }
}

struct NativeGlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 1)
            }
    }
}

struct AppleProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .buttonStyle(.borderedProminent)
    }
}

struct ClearButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var prominence: Prominence = .standard

    enum Prominence {
        case standard
        case primary
        case danger
    }

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .opacity(configuration.isPressed ? 0.86 : 1)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return label
            .background(backgroundColor(configuration.isPressed), in: shape)
            .overlay {
                shape.stroke(borderColor, lineWidth: 1)
            }
            .contentShape(shape)
    }

    private var foregroundColor: Color {
        switch prominence {
        case .standard:
            .primary
        case .primary:
            .primary
        case .danger:
            .red
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch prominence {
        case .standard:
            colorScheme == .dark
                ? Color.white.opacity(isPressed ? 0.24 : 0.16)
                : Color.black.opacity(isPressed ? 0.095 : 0.060)
        case .primary:
            Color.accentColor.opacity(isPressed ? 0.82 : 1)
        case .danger:
            colorScheme == .dark
                ? Color.red.opacity(isPressed ? 0.28 : 0.18)
                : Color.red.opacity(isPressed ? 0.20 : 0.12)
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .standard:
            colorScheme == .dark ? .white.opacity(0.24) : .black.opacity(0.18)
        case .primary:
            .white.opacity(0.28)
        case .danger:
            .red.opacity(colorScheme == .dark ? 0.45 : 0.34)
        }
    }
}


struct MacHoverLift: ViewModifier {
    var disabled = false
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(disabled || !hovered ? 1 : 1.006)
            .shadow(color: .black.opacity(disabled || !hovered ? 0 : 0.10), radius: 8, y: 3)
            .animation(.easeOut(duration: 0.16), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 18, padding: CGFloat = 26) -> some View {
        modifier(GlassPanel(radius: radius, padding: padding))
    }

    func macHoverLift(disabled: Bool = false) -> some View {
        modifier(MacHoverLift(disabled: disabled))
    }

    func nativeGlassSurface(radius: CGFloat = 16) -> some View {
        modifier(NativeGlassSurface(radius: radius))
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
                HStack(spacing: 5) {
                    Image(systemName: "apple.logo")
                        .font(.caption2.weight(.medium))
                    Text("为 macOS 设计的本地加密笔记")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct CeremonyToast: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(width: 32, height: 32)
                .background(.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .nativeGlassSurface(radius: 16)
    }
}

struct VaultSealAnimation: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    var active: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.mint.opacity(active ? 0.0 : 0.26), lineWidth: 1.4)
                    .scaleEffect(active && !reduceMotion ? 1.18 + CGFloat(index) * 0.10 : 0.86 + CGFloat(index) * 0.06)
                    .opacity(active ? 0 : 1)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.72).delay(Double(index) * 0.08),
                        value: active
                    )
            }
            Image(systemName: active ? "checkmark.seal.fill" : "lock.shield.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(active ? .mint : .secondary)
                .symbolEffect(.bounce, value: active)
        }
        .frame(width: 86, height: 86)
        .background(.quaternary.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct VaultIntakeVisual: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var sealed = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.mint.opacity(0.16))
                Image(systemName: sealed ? "lock.rectangle.stack.fill" : "doc.badge.arrow.up.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.mint)
                    .scaleEffect(sealed && !reduceMotion ? 1.08 : 1)
                    .animation(.easeInOut(duration: 0.28), value: sealed)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(sealed ? "正在封存文件" : "正在接收文件")
                    .font(.headline)
                Text(sealed ? "分片加密写入保险柜，完成后会移除原文件。" : "文件已进入本地加密流程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
        .padding(14)
        .nativeGlassSurface(radius: 18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                sealed = true
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
                    introRow("person.2.fill", "多账号", "每个账户平等独立，便于多人共用同一台 Mac。")
                    introRow("checkmark.seal.fill", "纯免费", "所有本地功能都可直接使用，没有会员、广告或购买入口。")
                    introRow("hand.raised.fill", "隐私优先", "账户只能管理自己的数据，不能删除或查看其他账户内容。")
                }
                Text("接下来创建你的第一个本地账户。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("原生 macOS 体验 · 完全本地运行", systemImage: "apple.logo")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("开始使用") { onContinue() }
                        .buttonStyle(AppleProminentButtonStyle())
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

struct MigrationView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var username = ""
    @State private var oldPassword = ""

    var body: some View {
        VStack(spacing: 24) {
            BrandHeader()
            VStack(alignment: .leading, spacing: 14) {
                Text("升级旧保险库").font(.title2.bold())
                Text("这一步会保留旧笔记，并把旧密码作为这个本地账户的登录密码。")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("旧版用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                SecureField("旧版主密码 / 新用户登录密码", text: $oldPassword)
                    .textFieldStyle(.roundedBorder)
                ErrorText(store.errorMessage)
                Button("升级并进入") {
                    store.migrateLegacyVault(
                        username: username,
                        oldPassword: oldPassword
                    )
                    oldPassword = ""
                }
                .buttonStyle(AppleProminentButtonStyle()).controlSize(.large)
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

private struct AuthFormHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PasswordStrengthIndicator: View {
    let password: String

    private var score: Int {
        guard !password.isEmpty else { return 0 }
        var value = 0
        if password.count >= 8 { value += 1 }
        if password.count >= 12 { value += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { value += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { value += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { value += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { value += 1 }
        return min(value, 5)
    }

    private var label: String {
        switch score {
        case 0: "输入密码后显示强度"
        case 1...2: "偏弱，建议至少 12 位并混合字母、数字和符号"
        case 3...4: "可用，继续增加长度会更稳"
        default: "强度较好，请务必保存恢复码"
        }
    }

    private var tint: Color {
        switch score {
        case 0: .secondary
        case 1...2: .orange
        case 3...4: .blue
        default: .mint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, proxy.size.width * CGFloat(score) / 5))
                }
            }
            .frame(height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("密码强度：\(label)")
    }
}

struct UnlockView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var mode: AuthMode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var recoveryCode = ""
    @State private var selectedAccountID: UUID?
    @State private var formHeight: CGFloat = 240
    @FocusState private var focused: Bool

    private var selectedAccount: AccountSummary? {
        guard let selectedAccountID else { return nil }
        return store.accounts.first { $0.id == selectedAccountID }
    }

    private var canSubmitLogin: Bool {
        !store.accounts.isEmpty || !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 18) {
            BrandHeader()
                .accessibilityAddTraits(.isHeader)

            authenticationPanel

            Text("本地账户 · 各自加密 · 无云端")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .onAppear {
            mode = store.userCount == 0 ? .register : .login
            selectedAccountID = selectedAccountID ?? store.accounts.first?.id
            focused = true
        }
        .onChange(of: store.accounts) { _, accounts in
            if selectedAccountID == nil || !accounts.contains(where: { $0.id == selectedAccountID }) {
                selectedAccountID = accounts.first?.id
            }
            if accounts.isEmpty {
                mode = .register
            }
        }
        .onChange(of: selectedAccountID) { _, _ in
            password = ""
        }
    }

    private var authenticationPanel: some View {
        VStack(spacing: 14) {
            Picker("账户操作", selection: $mode) {
                ForEach(AuthMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .accessibilityLabel("账户操作")

            ZStack(alignment: .top) {
                VStack(spacing: 14) {
                    activeAuthenticationForm
                        .id(mode)
                        .transition(authFormTransition)

                    if let error = store.errorMessage {
                        ErrorText(error)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: AuthFormHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .frame(height: formHeight, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: 420)
        .glassPanel(radius: 20, padding: 22)
        .frame(maxWidth: 468)
        .onPreferenceChange(AuthFormHeightKey.self) { height in
            guard height > 1, abs(height - formHeight) > 0.5 else { return }
            if reduceMotion {
                formHeight = height
            } else {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    formHeight = height
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: mode)
    }

    @ViewBuilder
    private var activeAuthenticationForm: some View {
        switch mode {
        case .login:
            loginForm
        case .register:
            registerForm
        case .recover:
            recoveryForm
        }
    }

    private var authFormTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -5))
        )
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                        Text(selectedAccount.displayName)
                            .font(.caption)
                        Spacer()
                        Text("密码登录")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("本版本只使用账户密码和恢复码，不再使用设备级生物识别解锁。")
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
                .buttonStyle(AppleProminentButtonStyle()).controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!canSubmitLogin)
                .keyboardShortcut(.defaultAction)
            if store.userCount == 0 {
                Text("还没有用户，请切到“注册”创建第一个用户。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var registerForm: some View {
        VStack(spacing: 14) {
            TextField("新用户名", text: $username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .focused($focused)
            if store.userCount == 0 {
                Text("第一个账户会创建这台 Mac 上的本地保险库。之后也可以继续创建其他平等账户。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecureField("用户密码", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("再次输入用户密码", text: $confirmation)
                .textFieldStyle(.roundedBorder)
                .onSubmit(register)
            PasswordStrengthIndicator(password: password)
            Button("注册并进入", action: register)
                .buttonStyle(AppleProminentButtonStyle()).controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
            Text("每个本地账户都由自己的密码和恢复码保护。")
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
            PasswordStrengthIndicator(password: password)
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
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            password = ""
        }
    }

    private func register() {
        store.registerUser(
            username: username,
            password: password,
            confirmation: confirmation
        )
        if store.state == .unlocked {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
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
    @StateObject private var searchIndex = NoteSearchIndex()
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
        if searchIndex.effectiveQuery.isEmpty {
            notes = baseNotes
        } else {
            notes = baseNotes.filter(searchIndex.matches)
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
        "本地账户 · 纯免费"
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceSwitcher
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

            mainStatusStrip
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
                .frame(minHeight: 54)
                .background(.bar)

            ZStack {
                if workspaceMode == .notes {
                    notesBody
                } else {
                    VaultView()
                        .environmentObject(store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The native segmented control supplies selection feedback. Avoid
            // sliding two large split views, which made headers flash on switching.
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .toolbar(content: workspaceToolbar)
        .toolbarBackground(.bar, for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesAddAttachments)) { _ in
            workspaceMode = .vault
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cipherNotesOpenVaultImporter, object: nil)
            }
        }
    }

    private var workspaceSwitcher: some View {
        Picker("区域", selection: $workspaceMode) {
            ForEach(WorkspaceMode.allCases) { mode in
                Label(
                    mode.rawValue,
                    systemImage: mode == .notes ? "note.text" : "lock.rectangle.stack.fill"
                )
                .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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
                    protectionStatusBadge
                    Picker("筛选", selection: $noteFilterRawValue) {
                        ForEach(NoteFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.regular)
                    .frame(height: 30)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                List(selection: $selection) {
                    ForEach(filteredNotes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                HStack(spacing: 5) {
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
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(note.updatedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Text(notePreviewText(for: note))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !note.tags.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption2)
                                            .foregroundStyle(.mint)
                                    }
                                }
                                .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
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
                .overlay {
                    if filteredNotes.isEmpty {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                emptyNotesTitle,
                                systemImage: "note.text.badge.plus",
                                description: Text(emptyNotesDescription)
                            )
                            Button {
                                selection = store.addNote()
                            } label: {
                                Label("新建第一条笔记", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(AppleProminentButtonStyle())
                        }
                        .padding()
                    }
                }
                .searchable(text: $searchIndex.query, prompt: "搜索已解锁的笔记")
                HStack {
                    Button { selection = store.addNote() } label: { Label("新笔记", systemImage: "square.and.pencil") }
                    Spacer()
                    Text("\(activeNotesCount) 条 · 归档 \(archivedNotesCount)").foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
            .background(.background)
        } detail: {
            if let selection, store.notes.contains(where: { $0.id == selection }) {
                NoteEditor(noteID: selection)
            } else {
                ContentUnavailableView("选择一条笔记", systemImage: "note.text", description: Text("或创建一条新的加密笔记"))
            }
        })
        .listStyle(.sidebar)
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

    private var protectionStatusBadge: some View {
        Label(
            store.currentAccountAdvancedDataProtectionEnabled ? "最高保护模式已开启" : "标准保护模式",
            systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield"
        )
        .font(.caption)
        .foregroundStyle(store.currentAccountAdvancedDataProtectionEnabled ? .mint : .secondary)
        .lineLimit(1)
    }

    private var mainStatusStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            mainStatusPill(
                "当前账户",
                value: store.signedInUsername ?? "未登录",
                systemImage: "person.crop.circle.fill",
                tint: .accentColor
            )
            mainStatusPill(
                "保护模式",
                value: store.currentAccountAdvancedDataProtectionEnabled ? "最高保护" : "标准保护",
                systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield",
                tint: store.currentAccountAdvancedDataProtectionEnabled ? .accentColor : .secondary
            )
            mainStatusPill(
                "自动锁定",
                value: "\(store.autoLockMinutes) 分钟",
                systemImage: "timer",
                tint: .secondary
            )
            mainStatusPill(
                "保险柜",
                value: "\(store.vaultItems.count) 个文件",
                systemImage: "lock.rectangle.stack.fill",
                tint: .secondary
            )
        }
    }

    private var emptyNotesTitle: String {
        if !searchIndex.query.isEmpty { return "没有匹配的笔记" }
        if (NoteFilter(rawValue: noteFilterRawValue) ?? .active) == .archived { return "归档是空的" }
        return "还没有笔记"
    }

    private var emptyNotesDescription: String {
        if !searchIndex.query.isEmpty { return "换个关键词，或直接创建一条新的加密笔记。" }
        return "新建后会自动保存在当前本地账户的加密保险库里。"
    }

    private func mainStatusPill(_ title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
    private func workspaceToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                if workspaceMode == .notes {
                    notesToolbarMenu
                } else {
                    vaultToolbarMenu
                }
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
    private var vaultToolbarMenu: some View {
        Button {
            NotificationCenter.default.post(name: .cipherNotesOpenVaultImporter, object: nil)
        } label: {
            Label("移入照片或文件…", systemImage: "tray.and.arrow.down.fill")
        }
        Divider()
        Button { backupVault() } label: {
            Label("备份保险库…", systemImage: "externaldrive.badge.plus")
        }
        Button { restoreVault() } label: {
            Label("从备份还原…", systemImage: "arrow.counterclockwise.icloud")
        }
        Divider()
        Button {
            store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
        } label: {
            Label(
                store.currentAccountAdvancedDataProtectionEnabled ? "关闭最高保护模式" : "开启最高保护模式",
                systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield"
            )
        }
        Button {
            store.rotateRecoveryCode()
        } label: {
            Label("生成新的恢复码", systemImage: "key.fill")
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
        .disabled(store.currentAccountAdvancedDataProtectionEnabled)
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
        Button { togglePinnedSelectedNote() } label: {
            Label("置顶 / 取消置顶", systemImage: "pin.fill")
        }
            .disabled(selectedNote == nil)
        Button { toggleFavoriteSelectedNote() } label: {
            Label("收藏 / 取消收藏", systemImage: "star.fill")
        }
            .disabled(selectedNote == nil)
        Button { toggleArchivedSelectedNote() } label: {
            Label("归档 / 移回", systemImage: "archivebox.fill")
        }
            .disabled(selectedNote == nil)
        Divider()
        Button { copySelectedNote() } label: {
            Label("复制所选笔记内容", systemImage: "doc.on.doc")
        }
            .disabled(selectedNote == nil || store.currentAccountAdvancedDataProtectionEnabled)
        Button { duplicateSelectedNote() } label: {
            Label("复制所选笔记为新笔记", systemImage: "plus.square.on.square")
        }
            .disabled(selectedNote == nil)
        Divider()
        Button { exportSelectedPlainNote(fileExtension: "md") } label: {
            Label("导出所选笔记为 Markdown…", systemImage: "doc.text")
        }
            .disabled(selectedNote == nil || store.currentAccountAdvancedDataProtectionEnabled)
        Button { exportSelectedPlainNote(fileExtension: "txt") } label: {
            Label("导出所选笔记为 TXT…", systemImage: "doc.plaintext")
        }
            .disabled(selectedNote == nil || store.currentAccountAdvancedDataProtectionEnabled)
        Button { showingExportShare = true } label: {
            Label("导出所选笔记为共享文件", systemImage: "square.and.arrow.up")
        }
            .disabled(selectedNote == nil || store.currentAccountAdvancedDataProtectionEnabled)
        Button { chooseSharedFile() } label: {
            Label("导入共享文件", systemImage: "square.and.arrow.down")
        }
            .disabled(store.currentAccountAdvancedDataProtectionEnabled)
        Divider()
        Button {
            store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
        } label: {
            Label(
                store.currentAccountAdvancedDataProtectionEnabled ? "关闭最高保护模式" : "开启最高保护模式",
                systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield"
            )
        }
        Button {
            store.rotateRecoveryCode()
        } label: {
            Label("生成新的恢复码", systemImage: "key.fill")
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
        if store.blockAdvancedProtectionAction("高级数据保护已开启，复制笔记内容已阻止") { return }
        let title = note.title.isEmpty ? "无标题" : note.title
        let text = note.body.isEmpty ? title : "\(title)\n\n\(note.body)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.errorMessage = "笔记内容已复制到剪贴板"
        store.recordSecurityEvent(.noteCopied, message: "已复制 1 条笔记内容")
    }

    private func showShareExportForSelectedNote() {
        if store.blockAdvancedProtectionAction("高级数据保护已开启，共享导出已阻止") { return }
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
        if store.blockAdvancedProtectionAction("高级数据保护已开启，普通导出已阻止") { return }
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
            store.recordSecurityEvent(.noteExported, message: "已导出 1 条普通笔记")
        } catch {
            store.errorMessage = "导出失败：\(error.localizedDescription)"
            store.recordSecurityEvent(.noteExported, result: .failure, message: "普通笔记导出失败")
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
        guard let auth = requestDangerAuthorization(
            title: "确认当前账户",
            message: "请输入当前账户密码，并输入“还原保险库”继续。",
            confirmationPrompt: "输入：还原保险库"
        ) else { return }
        store.restoreVault(from: url, currentPassword: auth.password, confirmationText: auth.confirmation)
    }


    private func chooseSharedFile() {
        if store.blockAdvancedProtectionAction("高级数据保护已开启，共享导入已阻止") { return }
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

    private var saveStatusText: String {
        savePending ? "正在保存" : "已保存"
    }

    private var saveStatusIcon: String {
        savePending ? "arrow.triangle.2.circlepath" : "checkmark.circle"
    }

    private var saveStatusTint: Color {
        savePending ? .orange : .mint
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
                    Button {
                        saveNow()
                    } label: {
                        Label("立即保存", systemImage: "tray.and.arrow.down.fill")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!savePending)
                }
            }
            .buttonStyle(ClearButtonStyle())
            .padding(.horizontal, 28).padding(.top, 24)
            if let note {
                ViewThatFits(in: .horizontal) {
                    editorMetaRow(note: note)
                    editorCompactMeta(note: note)
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
        .background(.background)
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

    private func editorMetaRow(note: Note) -> some View {
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
            Label(saveStatusText, systemImage: saveStatusIcon)
                .foregroundStyle(saveStatusTint)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.86)
    }

    private func editorCompactMeta(note: Note) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("最后更新 \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            Text("\(characterCount) 字符 · \(wordCount) 词 · \(lineCount) 行 · 约 \(readingMinutes) 分钟")
            Label(saveStatusText, systemImage: saveStatusIcon)
                .foregroundStyle(saveStatusTint)
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
            store.updateNote(id: id, title: title, body: body, tags: tags)
            savePending = false
        }
    }

    private func saveNow() {
        guard loadedNoteID == noteID else { return }
        store.updateNote(id: noteID, title: draftTitle, body: draftBody, tags: parsedTags)
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
    @State private var intakeActive = false
    @State private var previousVaultCount = 0
    @State private var ceremonyMessage: String?
    @State private var ceremonyDismissTask: Task<Void, Never>?

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
        if store.currentAccountAdvancedDataProtectionEnabled { return items }
        guard !query.isEmpty else { return items }
        return items.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
    }

    private var totalByteCount: Int {
        store.vaultItems.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                vaultHeader

                if intakeActive {
                    VaultIntakeVisual()
                        .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                }

                if !store.vaultImportJobs.isEmpty {
                    vaultImportQueue
                        .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索保险柜文件", text: $query)
                        .textFieldStyle(.plain)
                        .disabled(store.currentAccountAdvancedDataProtectionEnabled)
                    if store.currentAccountAdvancedDataProtectionEnabled {
                        Label("最高保护已隐藏文件名", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                }

                ViewThatFits(in: .horizontal) {
                    vaultFilterRow
                    VStack(alignment: .leading, spacing: 8) {
                        vaultFilterPicker
                        vaultCountText
                    }
                }

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        store.vaultItems.isEmpty ? "保险柜是空的" : "没有匹配的文件",
                        systemImage: "lock.rectangle",
                        description: Text("点“移入照片或文件”，应用会先加密保存，再删除原文件。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(filteredItems) { item in
                            VaultItemCard(item: item)
                                .environmentObject(store)
                                .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                                .macHoverLift(disabled: reduceMotion)
                        }
                    }
                    .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: filteredItems.map(\.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .scrollIndicators(.automatic)
        .overlay(alignment: .bottom) {
            if let ceremonyMessage {
                CeremonyToast(
                    systemImage: "checkmark.seal.fill",
                    title: ceremonyMessage,
                    detail: "文件已写入本地加密保险柜。"
                )
                .frame(maxWidth: 380)
                .padding(.bottom, 18)
                .transition(MotionStyle.transition(reduceMotion: reduceMotion))
            }
        }
        .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: intakeActive)
        .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: ceremonyMessage)
        .onAppear {
            previousVaultCount = store.vaultItems.count
        }
        .onChange(of: store.vaultItems.count) { oldValue, newValue in
            if newValue > oldValue {
                let imported = newValue - oldValue
                intakeActive = false
                showCeremony(imported == 1 ? "加密完成" : "\(imported) 个文件加密完成")
            }
            previousVaultCount = newValue
        }
        .onChange(of: store.errorMessage) { _, message in
            if message != nil {
                intakeActive = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesOpenVaultImporter)) { _ in
            chooseVaultFiles()
        }
        .alert("密笺", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var vaultHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                vaultTitleBlock
                Spacer()
                vaultImportButton
            }
            VStack(alignment: .leading, spacing: 12) {
                vaultTitleBlock
                vaultImportButton
            }
        }
        .frame(minHeight: 58, alignment: .topLeading)
    }

    private var vaultTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("保险柜", systemImage: "lock.rectangle.stack.fill")
                .font(.title2.bold())
            Text("照片和文件独立保存在保险柜里。移入成功后，原文件会从原位置删除。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vaultImportButton: some View {
        Button {
            chooseVaultFiles()
        } label: {
            Label("移入照片或文件", systemImage: "tray.and.arrow.down.fill")
        }
        .buttonStyle(AppleProminentButtonStyle())
        .controlSize(.regular)
    }

    private var vaultFilterRow: some View {
        HStack(spacing: 12) {
            vaultFilterPicker
            Spacer(minLength: 12)
            vaultCountText
        }
    }

    private var vaultFilterPicker: some View {
        Picker("文件类型", selection: $filter) {
            ForEach(VaultFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .frame(height: 30)
        .frame(maxWidth: 460)
    }

    private var vaultCountText: some View {
        Text("\(store.vaultItems.count) 个文件 · \(ByteCountFormatter.string(fromByteCount: Int64(totalByteCount), countStyle: .file))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }

    private func chooseVaultFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "移入保险柜后，原照片/原文件会从原位置删除"
        panel.prompt = "加密并删除原文件"
        guard panel.runModal() == .OK else { return }
        intakeActive = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        store.importFilesToVault(urls: panel.urls, deleteOriginals: true)
    }

    private var vaultImportQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("导入队列", systemImage: "arrow.down.doc.fill")
                    .font(.headline)
                Spacer()
                if store.vaultImportJobs.contains(where: { !$0.isActive }) {
                    Button {
                        store.clearFinishedVaultImportJobs()
                    } label: {
                        Label("清除完成记录", systemImage: "checkmark.circle")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(ClearButtonStyle())
                    .font(.caption)
                }
            }
            ForEach(store.vaultImportJobs.prefix(4)) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: vaultImportIcon(for: job))
                            .foregroundStyle(vaultImportTint(for: job))
                        Text(job.fileName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(job.status.label)
                            .font(.caption)
                            .foregroundStyle(vaultImportTint(for: job))
                    }
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(job.processedByteCount), countStyle: .file))
                        Text("/")
                        Text(ByteCountFormatter.string(fromByteCount: Int64(job.byteCount), countStyle: .file))
                        if let remaining = job.estimatedRemainingSeconds {
                            Text("·")
                            Text("约 \(formattedRemainingTime(remaining))")
                        }
                        Spacer()
                        if job.status == .encrypting {
                            Button("暂停") {
                                store.pauseVaultImportJob(id: job.id)
                            }
                            .buttonStyle(ClearButtonStyle())
                            Button("取消") {
                                store.cancelVaultImportJob(id: job.id)
                            }
                            .buttonStyle(ClearButtonStyle())
                        } else if job.status == .paused {
                            Button("继续") {
                                store.resumeVaultImportJob(id: job.id)
                            }
                            .buttonStyle(ClearButtonStyle())
                            Button("取消") {
                                store.cancelVaultImportJob(id: job.id)
                            }
                            .buttonStyle(ClearButtonStyle())
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .nativeGlassSurface(radius: 16)
    }

    private func vaultImportIcon(for job: VaultImportJob) -> String {
        switch job.status {
        case .encrypting: "lock.rotation"
        case .paused: "pause.circle.fill"
        case .cancelling: "xmark.circle"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "minus.circle.fill"
        }
    }

    private func vaultImportTint(for job: VaultImportJob) -> Color {
        switch job.status {
        case .encrypting: .mint
        case .paused: .orange
        case .cancelling, .cancelled: .secondary
        case .finished: .green
        case .failed: .orange
        }
    }

    private func formattedRemainingTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(max(1, Int(seconds.rounded()))) 秒"
        }
        let minutes = Int(ceil(seconds / 60))
        return "\(minutes) 分钟"
    }

    private func showCeremony(_ message: String) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        ceremonyDismissTask?.cancel()
        ceremonyMessage = message
        ceremonyDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                ceremonyMessage = nil
            }
        }
    }
}

struct VaultItemCard: View {
    @EnvironmentObject private var store: VaultStore
    let item: VaultAttachment
    @State private var preview: NSImage?
    @State private var previewPayload: VaultPreviewPayload?

    var body: some View {
        let protected = store.currentAccountAdvancedDataProtectionEnabled
        let isDeleting = store.vaultDeletingItemIDs.contains(item.id)
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background.opacity(0.72))
                if protected {
                    VStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 34))
                            .foregroundStyle(.mint)
                        Text("最高保护已隐藏预览")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.28)
                        ProgressView("正在删除")
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .aspectRatio(1.55, contentMode: .fit)
            Text(protected ? "受保护文件" : item.fileName)
                .font(.headline)
                .lineLimit(2)
                .frame(height: 42, alignment: .topLeading)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                Spacer(minLength: 4)
                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 8) {
                Button {
                    openInternalPreview()
                } label: {
                    Label(protected ? "查看已禁用" : "查看", systemImage: protected ? "eye.slash" : "eye")
                        .frame(maxWidth: .infinity)
                }
                .disabled(protected || !canPreviewInternally)
                .buttonStyle(ClearButtonStyle(prominence: .primary))

                Menu {
                    Button {
                        exportItem()
                    } label: {
                        Label(protected ? "导出已禁用" : "导出文件", systemImage: "square.and.arrow.up")
                    }
                    .disabled(protected)
                    Button {
                        copyFileName()
                    } label: {
                        Label(protected ? "复制已禁用" : "复制文件名", systemImage: "doc.on.doc")
                    }
                    .disabled(protected)
                    Divider()
                    Button(role: .destructive) {
                        store.deleteVaultItem(itemID: item.id)
                    } label: {
                        Label("删除文件", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 32, height: 26)
                }
                .menuStyle(.borderlessButton)
                .help("更多文件操作")
                .disabled(isDeleting)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlassSurface(radius: 18)
        .allowsHitTesting(!isDeleting)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(protected ? "受保护的保险柜文件" : "保险柜文件：\(item.fileName)")
        .task(id: item.id) {
            if isImage && !store.currentAccountAdvancedDataProtectionEnabled {
                preview = await store.previewVaultImage(itemID: item.id)
            } else {
                preview = nil
            }
        }
        .sheet(item: $previewPayload, onDismiss: {
            previewPayload = nil
            store.clearSensitivePreviewCaches()
        }) { payload in
            VaultInternalPreviewView(payload: payload)
        }
    }

    private var isImage: Bool { item.contentType?.hasPrefix("image/") == true }
    private var isPDF: Bool { item.contentType == "application/pdf" || item.fileName.lowercased().hasSuffix(".pdf") }
    private var isText: Bool {
        item.contentType?.hasPrefix("text/") == true
        || ["txt", "md", "markdown", "json", "csv", "log", "xml", "yaml", "yml"].contains(item.fileName.lowercased().split(separator: ".").last.map(String.init) ?? "")
    }
    private var isAudio: Bool {
        item.contentType?.hasPrefix("audio/") == true
        || ["mp3", "m4a", "aac", "wav", "aiff", "caf"].contains(item.fileName.lowercased().split(separator: ".").last.map(String.init) ?? "")
    }
    private var isVideo: Bool {
        item.contentType?.hasPrefix("video/") == true
        || ["mp4", "mov", "m4v"].contains(item.fileName.lowercased().split(separator: ".").last.map(String.init) ?? "")
    }

    private var canPreviewInternally: Bool {
        !store.currentAccountAdvancedDataProtectionEnabled && (isImage || isPDF || isText || isAudio || isVideo)
    }

    private var systemImage: String {
        if item.contentType == "application/pdf" { return "doc.richtext" }
        if item.contentType?.hasPrefix("audio/") == true { return "waveform" }
        if item.contentType?.hasPrefix("video/") == true { return "film" }
        if item.contentType?.hasPrefix("text/") == true { return "doc.text" }
        return "doc.fill"
    }

    private func openInternalPreview() {
        if store.blockAdvancedProtectionAction("高级数据保护已开启，保险柜文件预览已阻止") { return }
        guard canPreviewInternally else {
            store.errorMessage = "这个文件类型暂不支持无落盘内置查看"
            return
        }
        guard let resource = store.makeVaultMediaResource(itemID: item.id) else { return }
        if isImage {
            previewPayload = VaultPreviewPayload(title: item.fileName, kind: .image(resource))
            return
        }
        if isPDF {
            previewPayload = VaultPreviewPayload(title: item.fileName, kind: .pdf(resource))
            return
        }
        if isText {
            previewPayload = VaultPreviewPayload(title: item.fileName, kind: .text(resource))
            return
        }
        if isAudio {
            previewPayload = VaultPreviewPayload(title: item.fileName, kind: .audio(resource))
            return
        }
        if isVideo {
            previewPayload = VaultPreviewPayload(title: item.fileName, kind: .video(resource))
            return
        }
        store.errorMessage = "这个文件无法在内置查看器中打开"
    }

    private func exportItem() {
        if store.blockAdvancedProtectionAction("高级数据保护已开启，保险柜文件导出已阻止") { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportVaultItem(itemID: item.id, to: url)
    }

    private func copyFileName() {
        if store.blockAdvancedProtectionAction("高级数据保护已开启，复制保险柜文件名已阻止") { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.fileName, forType: .string)
        store.errorMessage = "文件名已复制"
        store.recordSecurityEvent(.vaultFileNameCopied, message: "已复制 1 个保险柜文件名")
    }
}

private struct VaultPreviewPayload: Identifiable {
    let id = UUID()
    let title: String
    let kind: VaultPreviewKind
}

private enum VaultPreviewKind {
    case image(VaultMediaResource)
    case text(VaultMediaResource)
    case pdf(VaultMediaResource)
    case audio(VaultMediaResource)
    case video(VaultMediaResource)
}

private struct VaultInternalPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let payload: VaultPreviewPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.mint)
                    .frame(width: 30, height: 30)
                    .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("内置查看")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(ClearButtonStyle())
                .help("关闭查看器")
                .keyboardShortcut(.cancelAction)
            }

            Text("内容只在密笺内解密显示，关闭后会清理预览缓存。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 600, minHeight: 340, idealHeight: 460)
    }

    @ViewBuilder
    private var content: some View {
        switch payload.kind {
        case .image(let resource):
            VaultImagePreview(resource: resource)
        case .text(let resource):
            VaultTextPreview(resource: resource)
        case .pdf(let resource):
            VaultPDFResourcePreview(resource: resource)
        case .audio(let resource):
            VaultAudioPreview(resource: resource)
        case .video(let resource):
            VaultVideoPreview(resource: resource)
        }
    }

    private var iconName: String {
        switch payload.kind {
        case .image: "photo"
        case .text: "doc.text"
        case .pdf: "doc.richtext"
        case .audio: "waveform"
        case .video: "play.rectangle"
        }
    }
}

private struct VaultAudioPreview: View {
    @StateObject private var player: VaultMediaPlayer

    init(resource: VaultMediaResource) {
        _player = StateObject(wrappedValue: VaultMediaPlayer(resource: resource))
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.mint)
                .symbolEffect(.pulse, value: player.isPlaying)
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .accessibilityLabel("播放位置")
                .accessibilityValue("\(player.currentTime.formattedPlaybackTime)，共 \(player.duration.formattedPlaybackTime)")
                HStack {
                    Text(player.currentTime.formattedPlaybackTime)
                    Spacer()
                    Text(player.duration.formattedPlaybackTime)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Button {
                player.togglePlayback()
            } label: {
                Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(ClearButtonStyle(prominence: .primary))
            Text("按需解密播放，不写入明文临时文件，也不调用外部播放器。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDisappear { player.stopAndClear() }
    }
}

private struct VaultVideoPreview: View {
    @StateObject private var media: VaultMediaPlayer

    init(resource: VaultMediaResource) {
        _media = StateObject(wrappedValue: VaultMediaPlayer(resource: resource))
    }

    var body: some View {
        VStack(spacing: 10) {
            VideoPlayer(player: media.player)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let errorText = media.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text("视频按需解密播放，不写入明文临时文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { media.stopAndClear() }
    }
}

private struct VaultImagePreview: View {
    let resource: VaultMediaResource
    @State private var image: NSImage?
    @State private var errorText: String?
    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(1, proxy.size.width * zoom),
                                    height: max(1, proxy.size.height * zoom)
                                )
                        } else if let errorText {
                            ContentUnavailableView("无法显示图片", systemImage: "photo.badge.exclamationmark", description: Text(errorText))
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        } else {
                            ProgressView("正在安全解密图片")
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { zoom = max(0.5, zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("缩小")
                Slider(value: $zoom, in: 0.5...3, step: 0.25)
                    .frame(maxWidth: 180)
                Button { zoom = min(3, zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("放大")
                Button("适合窗口") { zoom = 1 }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .task(id: resource.id) {
            let reader = resource.reader
            let result = await Task.detached(priority: .userInitiated) { () -> Result<SendableNSImage, Error> in
                do {
                    let data = try reader.readAll(maximumBytes: 256 * 1024 * 1024)
                    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                        throw VaultError.corruptVault
                    }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096,
                        kCGImageSourceShouldCacheImmediately: true
                    ]
                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                        throw VaultError.corruptVault
                    }
                    return .success(SendableNSImage(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let imageBox): self.image = imageBox.image
            case .failure(let error): errorText = error.localizedDescription
            }
        }
    }
}

private struct VaultTextPreview: View {
    let resource: VaultMediaResource
    @State private var text: String?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .scrollIndicators(.automatic)
            } else if let errorText {
                ContentUnavailableView("无法显示文本", systemImage: "doc.badge.exclamationmark", description: Text(errorText))
            } else {
                ProgressView("正在安全解密文本")
            }
        }
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: resource.id) {
            let reader = resource.reader
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                do {
                    let data = try reader.readAll(maximumBytes: 16 * 1024 * 1024)
                    guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
                        throw VaultError.corruptVault
                    }
                    return .success(text)
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let text): self.text = text
            case .failure(let error): errorText = error.localizedDescription
            }
        }
    }
}

private struct VaultPDFResourcePreview: View {
    let resource: VaultMediaResource
    @State private var data: Data?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let data {
                VaultPDFPreview(data: data)
            } else if let errorText {
                ContentUnavailableView("无法显示 PDF", systemImage: "doc.badge.exclamationmark", description: Text(errorText))
            } else {
                ProgressView("正在安全解密 PDF")
            }
        }
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: resource.id) {
            let reader = resource.reader
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
                do { return .success(try reader.readAll(maximumBytes: 256 * 1024 * 1024)) }
                catch { return .failure(error) }
            }.value
            switch result {
            case .success(let data): self.data = data
            case .failure(let error): errorText = error.localizedDescription
            }
        }
    }
}

private extension TimeInterval {
    var formattedPlaybackTime: String {
        guard isFinite && self > 0 else { return "0:00" }
        let totalSeconds = Int(self.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

private struct VaultPDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = NoCopyPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(data: data)
    }
}

private final class NoCopyPDFView: PDFView {
    override var menu: NSMenu? {
        get { nil }
        set { }
    }

    override var acceptsFirstResponder: Bool { false }
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
            Text("共享密码不能为空，也不应过短。应用不会保存这个密码。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("选择保存位置", action: onExport)
                    .buttonStyle(AppleProminentButtonStyle())
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .buttonStyle(AppleProminentButtonStyle())
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text("应用不上传笔记、不提供云端恢复，也不保存明文用户密码、恢复码或共享密码。为方便登录页选择账户，账户显示名会保存在本机保险库文件中。忘记用户密码且没有恢复码时，相关笔记可能无法恢复。")
                    Text("最高保护模式会减少应用内预览、导出、复制、外部打开和失焦暴露，但它不是法律豁免、反取证承诺或对抗恶意软件的保证。拥有系统权限的恶意程序、屏幕录制、键盘记录、内存取证、备份软件或系统级日志仍可能造成泄露。")
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
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("快捷操作", systemImage: "wand.and.stars")
                        quickActionButtons
                    }
                    .securitySection()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionTitle("安全日志", systemImage: "list.bullet.rectangle.portrait.fill")
                            Spacer()
                            Picker("筛选", selection: $selectedLogCategory) {
                                ForEach(SecurityLogCategory.allCases) { category in
                                    Text(category.label).tag(category)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        Text("日志随当前账户加密保存，只记录事件、时间和结果，不记录笔记正文、文件内容、密码或恢复码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            Button {
                                exportSecurityLogs()
                            } label: {
                                Label("导出加密副本", systemImage: "lock.doc")
                            }
                            .disabled(store.securityLogs.isEmpty)
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

    private var quickActionButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
            Button {
                store.setAdvancedDataProtectionForCurrentAccount(!store.currentAccountAdvancedDataProtectionEnabled)
            } label: {
                Label(store.currentAccountAdvancedDataProtectionEnabled ? "关闭最高保护" : "开启最高保护", systemImage: "shield.lefthalf.filled")
            }
            .buttonStyle(ClearButtonStyle(prominence: store.currentAccountAdvancedDataProtectionEnabled ? .danger : .primary))
            Button {
                store.rotateRecoveryCode()
            } label: {
                Label("生成恢复码", systemImage: "key.fill")
            }
            .buttonStyle(.bordered)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentAccountAdvancedDataProtectionEnabled ? "最高保护模式正在运行" : "最高保护模式未开启")
                        .font(.headline)
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
        let alert = NSAlert()
        alert.messageText = "清空安全日志？"
        alert.informativeText = "这只会清空当前账户的本地安全日志，不会删除笔记或保险柜文件。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let auth = requestDangerAuthorization(
            title: "确认清空安全日志",
            message: "请输入当前账户密码，并输入“清空安全日志”继续。",
            confirmationPrompt: "输入：清空安全日志"
        ) else { return }
        store.clearSecurityLogs(currentPassword: auth.password, confirmationText: auth.confirmation)
    }

    private func exportSecurityLogs() {
        guard let auth = requestDangerAuthorization(
            title: "导出加密安全日志",
            message: "导出文件使用当前账户密码加密。请输入密码，并输入“导出安全日志”继续。",
            confirmationPrompt: "输入：导出安全日志"
        ) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cnaudit") ?? .data]
        panel.nameFieldStringValue = "CipherNotes-Security-Audit.cnaudit"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportEncryptedSecurityAudit(to: url, currentPassword: auth.password, confirmationText: auth.confirmation)
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
            id: "1.1.4",
            version: "1.1.4",
            title: "灵动登录面板",
            dateText: "2026-07-21",
            items: [
                "登录、注册和恢复三段选择栏保持固定位置与固定高度，不再随内容跳动。",
                "下方玻璃面板根据当前表单的实际高度平滑伸缩，并加入克制的弹性反馈。",
                "切换内容使用淡入与轻微位移动画，同时完整支持“减少动效”。",
                "面板顶部固定，增加内容时只向下展开；底部入口全部恢复直接显示，不再收进“更多”。",
                "发布版本更新为 1.1.4 (39)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.3",
            version: "1.1.3",
            title: "登录页渲染修复",
            dateText: "2026-07-21",
            items: [
                "移除可能在启动时渲染出空白窗口的登录页滚动容器路径。",
                "登录、注册和恢复恢复为稳定的原生窗口居中布局，并保持紧凑窗口下的完整可见性。",
                "自动界面检查新增前景内容断言，直接登录页若只剩背景会导致测试失败。",
                "发布版本更新为 1.1.3 (38)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.2",
            version: "1.1.2",
            title: "登录稳定性与安全入口",
            dateText: "2026-07-21",
            items: [
                "移除登录页依赖窗口几何信息的布局路径，修复窗口恢复后可能出现的空白界面。",
                "登录、注册和恢复统一使用稳定的原生滚动容器，任何窗口高度都能访问全部字段与操作。",
                "安全中心恢复为底部独立入口；外观与次要功能收进“更多”，不再占用主操作位置。",
                "发布版本更新为 1.1.2 (37)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.1",
            version: "1.1.1",
            title: "登录界面与窗口适配",
            dateText: "2026-07-21",
            items: [
                "登录、注册和恢复页改为按窗口高度自适应，不再依赖固定表单高度。",
                "普通窗口保持居中；窗口较矮时完整表单可自然滚动，字段和确认按钮不会被底部遮住。",
                "移除登录页切换时多余的固定留白，切换账户操作时的视觉重心更稳定。",
                "底部入口收进原生 macOS 菜单，外观、账户与安全、更新日志和法律声明仍完整保留，但不会横向溢出。",
                "发布版本更新为 1.1.1 (36)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.1.0",
            version: "1.1.0",
            title: "内置媒体与大文件体验",
            dateText: "2026-07-21",
            items: [
                "重构保险柜查看器：图片、PDF、文本、音频和视频统一在应用内查看，不再交给外部 App。",
                "音频与视频按需解密 4 MB 分块，不生成明文临时文件，大文件不再整体载入内存。",
                "图片缩略图改为后台降采样，并加入容量受控的 LRU 缓存；图片默认适合窗口并支持缩放。",
                "大文件导入支持暂停、继续和取消，大文件删除移到后台并显示处理状态。",
                "笔记搜索加入输入防抖和增量索引；备份增加 SHA-256 完整性清单，保险库保存增加损坏恢复副本。",
                "密码派生参数改为按账户版本化保存，安全日志可导出为加密审计副本。",
                "新增 860×620 浅色、深色和强调色自动渲染检查，GitHub Actions 更新到新运行时。",
                "发布版本更新为 1.1.0 (35)。"
            ]
        ),
        UpdateLogEntry(
            id: "1.0.9",
            version: "1.0.9",
            title: "安全加固与性能优化",
            dateText: "2026-07-21",
            items: [
                "笔记标题、正文和标签合并为一次加密写入，内容未变化时不再重复保存。",
                "4 MB 及以上文件改为后台加密导入，降低主界面卡顿。",
                "加入登录失败退避、共享密码必填、共享包大小限制和加密分块完整性校验。",
                "修改密码后自动更换恢复码，并加固账户删除、备份还原、导入取消和本地数据销毁流程。",
                "发布版本更新为 1.0.9 (34)。"
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
