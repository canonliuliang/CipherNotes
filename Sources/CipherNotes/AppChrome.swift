import SwiftUI

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


enum MotionStyle {
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

    static func workspaceTransition(fromLeading: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let offset = fromLeading ? -18.0 : 18.0
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: offset)),
            removal: .opacity.combined(with: .offset(x: -offset * 0.55))
        )
    }

    static func quick(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .easeInOut(duration: 0.20)
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

struct DeepAccessSequence {
    private(set) var nextIndex = 0
    private var lastTapAt: Date?

    mutating func register(index: Int, enabled: Bool, now: Date = .now) -> Bool {
        guard enabled else {
            reset()
            return false
        }
        if let lastTapAt, now.timeIntervalSince(lastTapAt) > 4 {
            reset()
        }
        lastTapAt = now
        if index == nextIndex {
            nextIndex += 1
            if nextIndex == 4 {
                reset()
                return true
            }
        } else {
            nextIndex = index == 0 ? 1 : 0
        }
        return false
    }

    mutating func reset() {
        nextIndex = 0
        lastTapAt = nil
    }
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
        ZStack(alignment: .topLeading) {
            AppBackground()
            rootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 860, minHeight: 620)
        .preferredColorScheme(appAppearance.colorScheme)
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
        .onChange(of: store.state) { _, state in
            guard state != .unlocked else { return }
            showingSecurityCenter = false
            showingUserManagement = false
            privacyShieldActive = false
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
            showingUserManagement = store.state == .unlocked
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

    @ViewBuilder
    private var rootContent: some View {
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
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 20, y: 10)
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
    @AppStorage("reduceMotion") private var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(
                Color.accentColor.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.16 : 0.28), lineWidth: 1)
            }
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.975)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.20, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }
}

struct ClearButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("reduceMotion") private var reduceMotion = false
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
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.975)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.20, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }

    private var foregroundColor: Color {
        switch prominence {
        case .standard:
            .primary
        case .primary:
            .white
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
            .scaleEffect(disabled || !hovered ? 1 : 1.012)
            .shadow(color: .black.opacity(disabled || !hovered ? 0 : 0.11), radius: 10, y: 4)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: hovered)
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
