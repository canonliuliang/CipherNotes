import AppKit
import AVKit
import PDFKit
import SwiftUI

enum VaultFileKind: Equatable {
    case image
    case video
    case audio
    case pdf
    case text
    case unsupported

    init(_ item: VaultAttachment) {
        let contentType = item.contentType?.lowercased() ?? ""
        let fileExtension = URL(fileURLWithPath: item.fileName).pathExtension.lowercased()
        if contentType.hasPrefix("image/") || ["heic", "heif", "jpg", "jpeg", "png", "gif", "tif", "tiff", "webp", "bmp"].contains(fileExtension) {
            self = .image
        } else if contentType.hasPrefix("video/") || ["mp4", "mov", "m4v"].contains(fileExtension) {
            self = .video
        } else if contentType.hasPrefix("audio/") || ["mp3", "m4a", "aac", "wav", "aiff", "caf"].contains(fileExtension) {
            self = .audio
        } else if contentType == "application/pdf" || fileExtension == "pdf" {
            self = .pdf
        } else if contentType.hasPrefix("text/") || ["txt", "md", "markdown", "json", "csv", "log", "xml", "yaml", "yml"].contains(fileExtension) {
            self = .text
        } else {
            self = .unsupported
        }
    }

    var isPreviewable: Bool { self != .unsupported }

    var symbolName: String {
        switch self {
        case .image: "photo.fill"
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .unsupported: "doc.fill"
        }
    }
}

struct VaultPreviewRequest: Identifiable {
    let id = UUID()
    let itemID: UUID
}

private enum LoadedVaultPreview {
    case image(NSImage)
    case text(String)
    case pdf(Data)
    case media(VaultMediaResource, isVideo: Bool)
}

struct VaultGalleryPreviewView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var currentItemID: UUID
    @State private var loadedPreview: LoadedVaultPreview?
    @State private var loading = true
    @State private var loadError: String?
    @State private var hoveringStage = false
    @State private var isWindowFullScreen = false
    private let onClose: (() -> Void)?

    init(initialItemID: UUID, onClose: (() -> Void)? = nil) {
        _currentItemID = State(initialValue: initialItemID)
        self.onClose = onClose
    }

    private var previewableItems: [VaultAttachment] {
        store.vaultItems
            .filter { VaultFileKind($0).isPreviewable }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var currentItem: VaultAttachment? {
        previewableItems.first { $0.id == currentItemID }
    }

    private var currentIndex: Int? {
        previewableItems.firstIndex { $0.id == currentItemID }
    }

    var body: some View {
        GeometryReader { geometry in
            let expanded = geometry.size.width >= 1_100 && geometry.size.height >= 720
            Group {
                if isWindowFullScreen {
                    ZStack {
                        viewerStage
                        VStack(spacing: 0) {
                            viewerHeader
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Spacer(minLength: 0)
                            if previewableItems.count > 1 {
                                filmstrip
                                    .padding(.horizontal, 10)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(16)
                    }
                } else {
                    VStack(alignment: .leading, spacing: expanded ? 12 : 10) {
                        viewerHeader
                        viewerStage
                        if previewableItems.count > 1 {
                            filmstrip
                        }
                    }
                    .padding(expanded ? 20 : 14)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 620, idealWidth: 920, maxWidth: .infinity, minHeight: 460, idealHeight: 680, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: currentItemID) {
            await loadCurrentItem()
        }
        .onAppear {
            isWindowFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isWindowFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isWindowFullScreen = false
        }
        .onDisappear {
            store.clearSensitivePreviewCaches()
        }
    }

    private var viewerHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: currentItem.map { VaultFileKind($0).symbolName } ?? "eye")
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentAccountAdvancedDataProtectionEnabled ? "受保护文件" : (currentItem?.fileName ?? "保险柜查看器"))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(positionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: isWindowFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ClearButtonStyle())
            .help(isWindowFullScreen ? "退出全屏" : "进入全屏")
            Button {
                closeViewer()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ClearButtonStyle())
            .help("关闭查看器")
            .keyboardShortcut(.cancelAction)
        }
        .frame(height: 34)
    }

    private var viewerStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.055))

            if let loadedPreview {
                previewContent(loadedPreview)
                    .id(currentItemID)
                    .transition(MotionStyle.transition(reduceMotion: reduceMotion))
            } else if let loadError, !loading {
                ContentUnavailableView("无法查看", systemImage: "exclamationmark.triangle", description: Text(loadError))
            }

            if loading {
                ZStack {
                    if loadedPreview != nil {
                        Color.black.opacity(0.08)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: currentItem.map { VaultFileKind($0).symbolName } ?? "lock.doc")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(store.currentAccountAdvancedDataProtectionEnabled ? "受保护内容" : (currentItem?.fileName ?? "保险柜文件"))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 320)
                        }
                    }
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在安全读取")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 18)
                }
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { navigationOverlay }
        .onHover { hoveringStage = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(MotionStyle.quick(reduceMotion: reduceMotion), value: loading)
        .animation(MotionStyle.quick(reduceMotion: reduceMotion), value: currentItemID)
    }

    @ViewBuilder
    private var navigationOverlay: some View {
        HStack {
            navigationButton(systemName: "chevron.left", help: "上一项", action: showPrevious)
                .disabled(!canShowPrevious)
                .opacity(canShowPrevious && (hoveringStage || reduceMotion) ? 1 : 0)
            Spacer()
            navigationButton(systemName: "chevron.right", help: "下一项", action: showNext)
                .disabled(!canShowNext)
                .opacity(canShowNext && (hoveringStage || reduceMotion) ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.16), value: hoveringStage)
        .allowsHitTesting(hoveringStage || reduceMotion)
    }

    private func navigationButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var filmstrip: some View {
        HStack(spacing: 10) {
            Button(action: showPrevious) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 30)
            }
            .disabled(!canShowPrevious)
            .keyboardShortcut(.leftArrow, modifiers: [])

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 7) {
                        ForEach(previewableItems) { item in
                            VaultGalleryThumbnail(item: item, selected: item.id == currentItemID) {
                                show(item.id)
                            }
                            .environmentObject(store)
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: currentItemID) { _, newValue in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            Button(action: showNext) {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 30)
            }
            .disabled(!canShowNext)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .buttonStyle(ClearButtonStyle())
        .frame(height: 48)
    }

    @ViewBuilder
    private func previewContent(_ preview: LoadedVaultPreview) -> some View {
        switch preview {
        case .image(let image):
            VaultImagePreview(image: image)
        case .text(let text):
            ScrollView {
                if store.currentAccountAdvancedDataProtectionEnabled {
                    previewText(text)
                        .textSelection(.disabled)
                } else {
                    previewText(text)
                        .textSelection(.enabled)
                }
            }
            .scrollIndicators(.automatic)
        case .pdf(let data):
            VaultPDFPreview(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .media(let resource, let isVideo):
            VaultStreamingMediaPreview(resource: resource, isVideo: isVideo)
        }
    }

    private func previewText(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }

    private var positionText: String {
        guard let currentIndex else { return "内置安全查看" }
        return "\(currentIndex + 1) / \(previewableItems.count) · 内置安全查看"
    }

    private var canShowPrevious: Bool { (currentIndex ?? 0) > 0 }
    private var canShowNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex + 1 < previewableItems.count
    }

    private func showPrevious() {
        guard let currentIndex, currentIndex > 0 else { return }
        show(previewableItems[currentIndex - 1].id)
    }

    private func showNext() {
        guard let currentIndex, currentIndex + 1 < previewableItems.count else { return }
        show(previewableItems[currentIndex + 1].id)
    }

    private func show(_ itemID: UUID) {
        guard itemID != currentItemID else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.08) : .easeInOut(duration: 0.18)) {
            currentItemID = itemID
        }
    }

    private func closeViewer() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func loadCurrentItem() async {
        loading = true
        loadError = nil
        if case .media? = loadedPreview {
            loadedPreview = nil
        }
        guard let item = currentItem else {
            loadedPreview = nil
            loading = false
            loadError = "文件已不存在"
            return
        }
        let requestedID = item.id
        let kind = VaultFileKind(item)
        if kind == .image, let cached = store.cachedVaultPreviewImage(itemID: requestedID) {
            loadedPreview = .image(cached)
        }
        let result: LoadedVaultPreview?
        switch kind {
        case .video, .audio:
            result = store.makeVaultMediaResource(itemID: requestedID).map {
                .media($0, isVideo: kind == .video)
            }
        case .image:
            if loadedPreview == nil,
               let thumbnail = await store.previewVaultImage(itemID: requestedID),
               !Task.isCancelled,
               currentItemID == requestedID {
                loadedPreview = .image(thumbnail)
            }
            result = await store.loadVaultImageForViewing(itemID: requestedID).map(LoadedVaultPreview.image)
        case .pdf:
            result = await store.loadVaultDocumentForViewing(itemID: requestedID, maximumBytes: 128 * 1024 * 1024).map(LoadedVaultPreview.pdf)
        case .text:
            if let data = await store.loadVaultDocumentForViewing(itemID: requestedID, maximumBytes: 5 * 1024 * 1024),
               let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) {
                result = .text(text)
            } else {
                result = nil
            }
        case .unsupported:
            result = nil
        }
        guard !Task.isCancelled, currentItemID == requestedID else { return }
        if let result {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                loadedPreview = result
                loading = false
            }
            if kind == .image {
                store.preloadVaultImages(around: requestedID)
            }
        } else {
            loadedPreview = nil
            loading = false
            loadError = kind == .unsupported ? "该文件格式暂不支持内置查看" : "无法安全读取该文件"
        }
    }
}

private struct VaultGalleryThumbnail: View {
    @EnvironmentObject private var store: VaultStore
    let item: VaultAttachment
    let selected: Bool
    let action: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary.opacity(0.75))
                if store.currentAccountAdvancedDataProtectionEnabled {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                } else if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: VaultFileKind(item).symbolName)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .task(id: item.id) {
            guard VaultFileKind(item) == .image,
                  !store.currentAccountAdvancedDataProtectionEnabled else {
                image = nil
                return
            }
            image = await store.previewVaultImage(itemID: item.id)
        }
    }
}

private struct VaultImagePreview: View {
    let image: NSImage
    @State private var zoom: CGFloat = 1
    @State private var fitRequestID = UUID()
    @State private var actualSizeRequestID = UUID()

    var body: some View {
        VStack(spacing: 8) {
            VaultZoomableImageView(
                image: image,
                zoom: $zoom,
                fitRequestID: fitRequestID,
                actualSizeRequestID: actualSizeRequestID
            )
                .background(Color.black.opacity(0.04))

            HStack(spacing: 9) {
                Button {
                    zoom = max(0.5, zoom - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("缩小")
                .keyboardShortcut("-", modifiers: [.command])

                Slider(value: $zoom, in: 0.5...8, step: 0.25)
                    .frame(maxWidth: 220)

                Button {
                    zoom = min(8, zoom + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("放大")
                .keyboardShortcut("+", modifiers: [.command])

                Button {
                    zoom = 1
                    fitRequestID = UUID()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .help("适合窗口")
                .keyboardShortcut("0", modifiers: [.command])

                Button {
                    actualSizeRequestID = UUID()
                } label: {
                    Text("1:1")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .help("按原始像素查看")
                .keyboardShortcut("1", modifiers: [.command])

                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.borderless)
            .frame(height: 26)
            .animation(.easeOut(duration: 0.16), value: zoom)
        }
    }
}

private struct VaultZoomableImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoom: CGFloat
    let fitRequestID: UUID
    let actualSizeRequestID: UUID

    func makeNSView(context: Context) -> VaultImageScrollView {
        let scrollView = VaultImageScrollView()
        scrollView.onZoomChanged = { newValue in
            if abs(zoom - newValue) > 0.01 { zoom = newValue }
        }
        scrollView.setImage(image)
        return scrollView
    }

    func updateNSView(_ scrollView: VaultImageScrollView, context: Context) {
        scrollView.onZoomChanged = { newValue in
            if abs(zoom - newValue) > 0.01 { zoom = newValue }
        }
        scrollView.setImage(image)
        scrollView.setRelativeZoom(zoom)
        scrollView.applyFitRequest(fitRequestID)
        scrollView.applyActualSizeRequest(actualSizeRequestID)
    }
}

@MainActor
final class VaultImageScrollView: NSScrollView {
    var onZoomChanged: ((CGFloat) -> Void)?

    private let imageView = NSImageView()
    private var displayedImage: NSImage?
    private var fitMagnification: CGFloat = 1
    private var requestedZoom: CGFloat = 1
    private var applyingZoom = false
    private var hasFittedImage = false
    private var lastViewportSize = NSSize.zero
    private var lastFitRequestID: UUID?
    private var lastActualSizeRequestID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let clipView = VaultCenteringClipView()
        clipView.drawsBackground = false
        contentView = clipView
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.01
        maxMagnification = 100
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        documentView = imageView
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let viewportSize = contentSize
        let viewportChanged = abs(viewportSize.width - lastViewportSize.width) > 1 || abs(viewportSize.height - lastViewportSize.height) > 1
        if viewportChanged { lastViewportSize = viewportSize }
        guard bounds.width > 1, bounds.height > 1 else { return }
        if !hasFittedImage || (viewportChanged && abs(relativeZoom - 1) < 0.02) {
            fitImageToWindow()
        }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        publishZoom()
    }

    override func smartMagnify(with event: NSEvent) {
        toggleZoom(at: documentPoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            toggleZoom(at: documentPoint(for: event))
            return
        }
        super.mouseDown(with: event)
    }

    func setImage(_ image: NSImage) {
        guard displayedImage !== image else { return }
        displayedImage = image
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: safeImageSize(image))
        requestedZoom = 1
        hasFittedImage = false
        needsLayout = true
    }

    func setRelativeZoom(_ value: CGFloat, centeredAt point: NSPoint? = nil) {
        requestedZoom = min(max(value, 0.5), 8)
        guard hasFittedImage else { return }
        let target = fitMagnification * requestedZoom
        guard abs(magnification - target) > 0.005 else { return }
        let anchor = point ?? documentVisibleRect.center
        let visibleBefore = documentVisibleRect
        let horizontalPosition = visibleBefore.width > 0
            ? (anchor.x - visibleBefore.minX) / visibleBefore.width
            : 0.5
        let verticalPosition = visibleBefore.height > 0
            ? (anchor.y - visibleBefore.minY) / visibleBefore.height
            : 0.5
        applyingZoom = true
        setMagnification(target, centeredAt: anchor)
        layoutSubtreeIfNeeded()
        let visibleAfter = documentVisibleRect
        contentView.scroll(to: NSPoint(
            x: anchor.x - horizontalPosition * visibleAfter.width,
            y: anchor.y - verticalPosition * visibleAfter.height
        ))
        reflectScrolledClipView(contentView)
        applyingZoom = false
        onZoomChanged?(requestedZoom)
    }

    func applyFitRequest(_ id: UUID) {
        guard lastFitRequestID != id else { return }
        lastFitRequestID = id
        requestedZoom = 1
        hasFittedImage = false
        if bounds.width > 1, bounds.height > 1 { fitImageToWindow() }
    }

    func applyActualSizeRequest(_ id: UUID) {
        guard lastActualSizeRequestID != nil else {
            lastActualSizeRequestID = id
            return
        }
        guard lastActualSizeRequestID != id else { return }
        lastActualSizeRequestID = id
        guard hasFittedImage, fitMagnification > 0 else { return }
        setRelativeZoom(1 / fitMagnification)
    }

    var relativeZoom: CGFloat {
        guard fitMagnification > 0 else { return 1 }
        return min(max(magnification / fitMagnification, 0.5), 8)
    }

    private func fitImageToWindow() {
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        minMagnification = 0.01
        maxMagnification = 100
        magnify(toFit: imageView.bounds)
        fitMagnification = max(magnification, 0.001)
        minMagnification = fitMagnification * 0.5
        maxMagnification = fitMagnification * 8
        hasFittedImage = true
        requestedZoom = 1
        onZoomChanged?(1)
    }

    private func publishZoom() {
        guard !applyingZoom else { return }
        requestedZoom = relativeZoom
        onZoomChanged?(requestedZoom)
    }

    private func toggleZoom(at point: NSPoint?) {
        if relativeZoom > 1.01 {
            setRelativeZoom(1)
        } else {
            setRelativeZoom(2, centeredAt: point)
        }
    }

    private func documentPoint(for event: NSEvent) -> NSPoint? {
        guard let documentView else { return nil }
        let point = documentView.convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: min(max(point.x, documentView.bounds.minX), documentView.bounds.maxX),
            y: min(max(point.y, documentView.bounds.minY), documentView.bounds.maxY)
        )
    }

    private func safeImageSize(_ image: NSImage) -> NSSize {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return NSSize(width: 1, height: 1)
        }
        return size
    }
}

private final class VaultCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }
        if documentView.frame.width < bounds.width {
            bounds.origin.x = (documentView.frame.width - bounds.width) / 2
        }
        if documentView.frame.height < bounds.height {
            bounds.origin.y = (documentView.frame.height - bounds.height) / 2
        }
        return bounds
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

private struct VaultStreamingMediaPreview: View {
    @StateObject private var player: VaultMediaPlayer
    @State private var scrubberValue: TimeInterval = 0
    @State private var scrubbing = false
    let isVideo: Bool

    init(resource: VaultMediaResource, isVideo: Bool) {
        _player = StateObject(wrappedValue: VaultMediaPlayer(resource: resource))
        self.isVideo = isVideo
    }

    var body: some View {
        VStack(spacing: 10) {
            if isVideo {
                VaultNativeVideoPlayer(player: player.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            } else {
                audioArtwork
                audioControls
            }

            if let errorText = player.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("媒体从加密分片按需读取，不写入临时明文文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .onDisappear { player.stopAndClear() }
    }

    private var audioArtwork: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, value: player.isPlaying)
            Text("加密音频流")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var audioControls: some View {
        VStack(spacing: 7) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubberValue : player.currentTime },
                    set: { scrubberValue = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubbing = true
                        scrubberValue = player.currentTime
                    } else {
                        player.seek(to: scrubberValue)
                        scrubbing = false
                    }
                }
            )
            .disabled(!player.isReady)
            HStack {
                Text((scrubbing ? scrubberValue : player.currentTime).formattedPlaybackTime)
                Spacer()
                Text(player.duration.formattedPlaybackTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                    .help("后退 10 秒")
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                    .help("前进 10 秒")
            }
            .buttonStyle(.borderless)
            .disabled(!player.isReady)
        }
    }
}

private struct VaultNativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
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

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document == nil {
            view.document = PDFDocument(data: data)
        }
    }
}

private final class NoCopyPDFView: PDFView {
    override var menu: NSMenu? {
        get { nil }
        set { }
    }

    override var acceptsFirstResponder: Bool { false }
}
