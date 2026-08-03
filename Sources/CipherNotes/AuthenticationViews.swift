import SwiftUI

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

struct PasswordStrengthIndicator: View {
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
                        .frame(width: score == 0 ? 0 : max(8, proxy.size.width * CGFloat(score) / 5))
                }
            }
            .frame(height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(score == 0 ? Color(nsColor: .secondaryLabelColor) : tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("密码强度：\(label)")
    }
}

struct UnlockView: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var mode: AuthMode?
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var recoveryCode = ""
    @State private var selectedAccountID: UUID?
    @FocusState private var focused: Bool

    private var selectedAccount: AccountSummary? {
        guard let selectedAccountID else { return nil }
        return store.accounts.first { $0.id == selectedAccountID }
    }

    private var selectedAccountPosition: String {
        guard let selectedAccountID,
              let index = store.accounts.firstIndex(where: { $0.id == selectedAccountID }) else {
            return "本机加密账户"
        }
        return "本机加密账户 · \(index + 1) / \(store.accounts.count)"
    }

    private var canSubmitLogin: Bool {
        !store.accounts.isEmpty || !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeMode: AuthMode {
        mode ?? (store.userCount == 0 ? .register : .login)
    }

    private var authenticationFormHeight: CGFloat {
        let errorHeight: CGFloat = store.errorMessage == nil ? 0 : 38
        switch activeMode {
        case .login:
            return 152 + errorHeight
        case .register:
            return (store.userCount == 0 ? 250 : 220) + errorHeight
        case .recover:
            return 290 + errorHeight
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    BrandHeader()
                        .accessibilityAddTraits(.isHeader)

                    authenticationPanel

                    Label("本地账户 · 各自加密 · 无云端", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(560, proxy.size.height), alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            mode = activeMode
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
        VStack(spacing: 16) {
            Picker("账户操作", selection: Binding(
                get: { activeMode },
                set: { mode = $0 }
            )) {
                ForEach(AuthMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .frame(maxWidth: .infinity)
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .labelsHidden()
            .accessibilityLabel("账户操作")

            ZStack(alignment: .top) {
                VStack(spacing: 14) {
                    activeAuthenticationForm
                        .id(activeMode)
                        .transition(authFormTransition)

                    if let error = store.errorMessage {
                        ErrorText(error)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: authenticationFormHeight, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: 440)
        .controlSize(.large)
        .glassPanel(radius: 20, padding: 20)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: authenticationFormHeight)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.90), value: activeMode)
    }

    @ViewBuilder
    private var activeAuthenticationForm: some View {
        switch activeMode {
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
                ZStack {
                    HStack(spacing: 12) {
                        ZStack(alignment: .leading) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .contentTransition(.symbolEffect(.replace))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedAccount?.displayName ?? "选择账户")
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(selectedAccountPosition)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .id(selectedAccountID)
                            .transition(accountSwitchTransition)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                    .background(.quaternary.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    }

                    Menu {
                        ForEach(store.accounts) { account in
                            Button {
                                withAnimation(MotionStyle.animation(reduceMotion: reduceMotion)) {
                                    selectedAccountID = account.id
                                }
                            } label: {
                                if account.id == selectedAccountID {
                                    Label(account.displayName, systemImage: "checkmark")
                                } else {
                                    Text(account.displayName)
                                }
                            }
                        }
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("选择账户")
                }
            }
            SecureField("用户密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(unlock)
                .id(selectedAccountID)
                .transition(.opacity)
            Button(action: unlock) {
                Label("登录", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(AppleProminentButtonStyle())
                .disabled(!canSubmitLogin)
                .keyboardShortcut(.defaultAction)
            if store.userCount == 0 {
                Text("还没有用户，请切到“注册”创建第一个用户。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: selectedAccountID)
    }

    private var accountSwitchTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 10)),
            removal: .opacity.combined(with: .offset(x: -7))
        )
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
            Button(action: register) {
                Label("注册并进入", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(AppleProminentButtonStyle())
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
            Button(action: resetPassword) {
                Label("用恢复码重设密码", systemImage: "key.viewfinder")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(AppleProminentButtonStyle())
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
        }
    }

    private func register() {
        store.registerUser(
            username: username,
            password: password,
            confirmation: confirmation
        )
        if store.state == .unlocked {
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
