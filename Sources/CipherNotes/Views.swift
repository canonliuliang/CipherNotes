import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let cipherNoteUTType = UTType(filenameExtension: "ciphernote") ?? .data

private func withSecurityScopedAccess<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    return try body()
}

@MainActor
func requestDangerAuthorization(title: String, message: String, confirmationPrompt: String) -> (password: String, confirmation: String)? {
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

@MainActor
func requestPasswordAuthorization(title: String, message: String, actionTitle: String) -> String? {
    let passwordField = NSSecureTextField()
    passwordField.placeholderString = "当前账户密码"
    passwordField.frame.size.width = 320

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.accessoryView = passwordField
    alert.addButton(withTitle: actionTitle)
    alert.addButton(withTitle: "取消")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let password = passwordField.stringValue
    return password.isEmpty ? nil : password
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
    @State private var noteColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var deepAccessSequence = DeepAccessSequence()
    @State private var showingDeepAccessAuthentication = false

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

    var body: some View {
        VStack(spacing: 0) {
            workspaceSwitcher
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Divider()
                }

            mainStatusStrip
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider() }

            ZStack {
                if workspaceMode == .notes {
                    notesBody
                        .transition(MotionStyle.workspaceTransition(fromLeading: true, reduceMotion: reduceMotion))
                } else {
                    VaultView()
                        .environmentObject(store)
                        .transition(MotionStyle.workspaceTransition(fromLeading: false, reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .top) {
                Divider()
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.30, dampingFraction: 0.90),
                value: workspaceMode
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar(content: workspaceToolbar)
        .toolbarBackground(.bar, for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesAddAttachments)) { _ in
            workspaceMode = .vault
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cipherNotesOpenVaultImporter, object: nil)
            }
        }
        .onChange(of: store.currentAccountAdvancedDataProtectionEnabled) { _, enabled in
            if !enabled {
                deepAccessSequence.reset()
                showingDeepAccessAuthentication = false
            }
        }
        .sheet(isPresented: $showingDeepAccessAuthentication) {
            DeepAccessAuthenticationView { password in
                guard store.enterSuperPrivateSpace(password: password) else { return false }
                selection = nil
                workspaceMode = .notes
                deepAccessSequence.reset()
                showingDeepAccessAuthentication = false
                return true
            }
            .environmentObject(store)
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
        .labelsHidden()
        .frame(width: 320, height: 30)
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    private var notesBody: some View {
        AnyView(NavigationSplitView(columnVisibility: $noteColumnVisibility) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("笔记", systemImage: "note.text")
                        .font(.headline)
                    Picker("筛选", selection: $noteFilterRawValue) {
                        ForEach(NoteFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
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
                    if filteredNotes.isEmpty && !query.isEmpty {
                        ContentUnavailableView("没有匹配的笔记", systemImage: "magnifyingglass")
                            .transition(.opacity)
                    }
                }
                .animation(MotionStyle.quick(reduceMotion: reduceMotion), value: filteredNotes.isEmpty)
                .animation(MotionStyle.quick(reduceMotion: reduceMotion), value: filteredNotes.map(\.id))
                .searchable(text: $query, prompt: "搜索已解锁的笔记")
                HStack {
                    if !store.notes.isEmpty {
                        Button { selection = store.addNote() } label: {
                            Label("新笔记", systemImage: "square.and.pencil")
                        }
                    }
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
            } else if store.notes.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "note.text.badge.plus").font(.system(size: 42)).foregroundStyle(.tertiary)
                    Text("开始写第一条笔记").font(.title3.weight(.semibold))
                    Text(emptyNotesDescription).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { selection = store.addNote() } label: { Label("新建笔记", systemImage: "square.and.pencil") }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: 420).frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
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

    private var mainStatusStrip: some View {
        HStack(spacing: 0) {
            mainStatusPill(
                store.isSuperPrivateSession ? "隔离会话" : "当前账户",
                value: store.isSuperPrivateSession ? "超级隐私空间" : (store.signedInUsername ?? "未登录"),
                systemImage: store.isSuperPrivateSession ? "lock.shield.fill" : "person.crop.circle.fill",
                tint: store.isSuperPrivateSession ? .mint : .accentColor,
                sequenceIndex: 0
            )
            Divider().frame(height: 28)
            mainStatusPill(
                "保护模式",
                value: store.currentAccountAdvancedDataProtectionEnabled ? "最高保护" : "标准保护",
                systemImage: store.currentAccountAdvancedDataProtectionEnabled ? "shield.lefthalf.filled" : "shield",
                tint: store.currentAccountAdvancedDataProtectionEnabled ? .accentColor : .secondary,
                sequenceIndex: 1
            )
            Divider().frame(height: 28)
            mainStatusPill(
                "自动锁定",
                value: "\(store.autoLockMinutes) 分钟",
                systemImage: "timer",
                tint: .secondary,
                sequenceIndex: 2
            )
            Divider().frame(height: 28)
            mainStatusPill(
                "保险柜",
                value: "\(store.vaultItems.count) 个文件",
                systemImage: "lock.rectangle.stack.fill",
                tint: .secondary,
                sequenceIndex: 3
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyNotesTitle: String {
        if !query.isEmpty { return "没有匹配的笔记" }
        if (NoteFilter(rawValue: noteFilterRawValue) ?? .active) == .archived { return "归档是空的" }
        return "还没有笔记"
    }

    private var emptyNotesDescription: String {
        if !query.isEmpty { return "换个关键词，或直接创建一条新的加密笔记。" }
        return "新建后会自动保存在当前本地账户的加密保险库里。"
    }

    private func mainStatusPill(
        _ title: String,
        value: String,
        systemImage: String,
        tint: Color,
        sequenceIndex: Int
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .animation(MotionStyle.quick(reduceMotion: reduceMotion), value: value)
        .onTapGesture {
            if deepAccessSequence.register(
                index: sequenceIndex,
                enabled: store.currentAccountAdvancedDataProtectionEnabled && !store.isSuperPrivateSession
            ) {
                showingDeepAccessAuthentication = true
            }
        }
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
            Button {
                SettingsRoute.open(.highestProtection)
            } label: {
                Label("安全中心", systemImage: "shield.checkered")
            }
            .help("安全中心")

            Button {
                SettingsRoute.open(.overview)
            } label: {
                Label("应用设置", systemImage: "gearshape")
            }
            .help("应用设置")

            Button {
                store.lock()
            } label: {
                Label(store.isSuperPrivateSession ? "退出并锁定" : "锁定", systemImage: "lock.fill")
            }
            .keyboardShortcut("l", modifiers: .command)
            .help(store.isSuperPrivateSession ? "退出超级隐私空间并锁定" : "立即锁定")
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
        store.showFeedback(.success, title: "笔记已复制")
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
            store.showFeedback(.success, title: "共享文件已导出")
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
            store.showFeedback(.success, title: fileExtension == "md" ? "Markdown 已导出" : "TXT 已导出")
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

private struct DeepAccessAuthenticationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var authenticationFailed = false
    let onAuthenticate: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: authenticationFailed)
                VStack(alignment: .leading, spacing: 3) {
                    Text("验证超级隐私空间")
                        .font(.title3.bold())
                    Text("此入口只属于当前账户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("请输入当前账户密码。进入后普通空间会从当前会话内存中清除，笔记和保险柜使用独立的加密数据区。退出时必须重新登录。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("当前账户密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(authenticate)

            if authenticationFailed {
                Label("密码不正确", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("验证并进入", action: authenticate)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func authenticate() {
        authenticationFailed = !onAuthenticate(password)
        if authenticationFailed {
            password = ""
            NSSound.beep()
        }
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
    @State private var intakeActive = false
    @State private var ceremonyMessage: String?
    @State private var ceremonyDismissTask: Task<Void, Never>?
    @State private var dropTargeted = false
    @State private var previewRequest: VaultPreviewRequest?

    private var filteredItems: [VaultAttachment] {
        let scoped = store.vaultItems.filter { item in
            let kind = VaultFileKind(item)
            return switch filter {
            case .all:
                true
            case .images:
                kind == .image
            case .documents:
                kind == .text
                || kind == .pdf
                || item.contentType?.contains("word") == true
                || item.contentType?.contains("spreadsheet") == true
            case .media:
                kind == .audio || kind == .video
            case .other:
                kind == .unsupported
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
                            VaultItemCard(item: item) { itemID in
                                previewRequest = VaultPreviewRequest(itemID: itemID)
                            }
                                .environmentObject(store)
                                .macHoverLift(disabled: reduceMotion)
                                .transition(MotionStyle.transition(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(MotionStyle.quick(reduceMotion: reduceMotion), value: filteredItems.map(\.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .scrollIndicators(.automatic)
        .dropDestination(for: URL.self) { urls, _ in
            importDroppedFiles(urls)
        } isTargeted: { targeted in
            withAnimation(MotionStyle.animation(reduceMotion: reduceMotion)) {
                dropTargeted = targeted
            }
        }
        .overlay {
            if dropTargeted {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.tint)
                            .symbolEffect(.bounce, value: dropTargeted)
                        Text("松开以移入保险柜")
                            .font(.title2.bold())
                        Text("文件会加密保存，成功后从原位置移除")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .nativeGlassSurface(radius: 18)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
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
        .onChange(of: store.vaultItems.count) { oldValue, newValue in
            if newValue > oldValue {
                let imported = newValue - oldValue
                intakeActive = false
                showCeremony(imported == 1 ? "加密完成" : "\(imported) 个文件加密完成")
            }
        }
        .onChange(of: store.errorMessage) { _, message in
            if message != nil {
                intakeActive = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cipherNotesOpenVaultImporter)) { _ in
            chooseVaultFiles()
        }
        .onDisappear {
            ceremonyDismissTask?.cancel()
        }
        .overlay {
            if let request = previewRequest {
                VaultGalleryPreviewView(initialItemID: request.itemID) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        previewRequest = nil
                    }
                }
                .environmentObject(store)
                .transition(.opacity)
                .zIndex(10)
            }
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
        store.importFilesToVault(urls: panel.urls, deleteOriginals: true)
    }

    private func importDroppedFiles(_ urls: [URL]) -> Bool {
        let files = urls.filter { url in
            guard url.isFileURL else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
        guard !files.isEmpty else { return false }
        intakeActive = true
        store.importFilesToVault(urls: files, deleteOriginals: true)
        return true
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
    let onPreview: (UUID) -> Void
    @State private var preview: NSImage?
    @State private var confirmingDeletion = false

    var body: some View {
        let protected = store.currentAccountAdvancedDataProtectionEnabled
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
            }
            .aspectRatio(1.55, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                if canPreviewInternally {
                    openInternalPreview()
                }
            }
            .help(canPreviewInternally ? "单击在密笺内查看" : "此格式暂不支持内置查看")
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
                    Label(protected ? "安全查看" : "查看", systemImage: protected ? "eye.fill" : "eye")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canPreviewInternally)
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
                        confirmingDeletion = true
                    } label: {
                        Label("删除文件", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 32, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("更多文件操作")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlassSurface(radius: 18)
        .task(id: item.id) {
            if fileKind == .image && !store.currentAccountAdvancedDataProtectionEnabled {
                preview = await store.previewVaultImage(itemID: item.id)
            } else {
                preview = nil
            }
        }
        .confirmationDialog("永久删除这个保险柜文件？", isPresented: $confirmingDeletion) {
            Button("删除文件", role: .destructive) { store.deleteVaultItem(itemID: item.id) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("加密文件会立即删除，无法撤销。")
        }
    }

    private var fileKind: VaultFileKind { VaultFileKind(item) }
    private var canPreviewInternally: Bool { fileKind.isPreviewable }

    private var systemImage: String {
        fileKind.symbolName
    }

    private func openInternalPreview() {
        guard canPreviewInternally else {
            store.showFeedback(.warning, title: "暂不支持内置查看", detail: "该文件类型不会在外部应用中打开")
            return
        }
        if fileKind == .text && item.byteCount > 5 * 1024 * 1024 {
            store.showFeedback(.warning, title: "文本文件过大", detail: "内置查看上限为 5 MB")
            return
        }
        onPreview(item.id)
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
        store.showFeedback(.success, title: "文件名已复制")
        store.recordSecurityEvent(.vaultFileNameCopied, message: "已复制 1 个保险柜文件名")
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
            Text("共享密码不能留空。请使用不重复的长密码，并通过与共享文件不同的渠道发送。应用不会保存它。")
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
