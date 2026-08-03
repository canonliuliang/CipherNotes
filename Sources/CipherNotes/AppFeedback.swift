import SwiftUI

enum AppFeedbackKind: String, Equatable, Sendable {
    case success, info, warning, failure, progress

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        case .progress: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .success: .green
        case .info, .progress: .accentColor
        case .warning: .orange
        case .failure: .red
        }
    }
}

struct AppFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: AppFeedbackKind
    let title: String
    let detail: String?
}

struct PendingNoteDeletion: Equatable, Sendable {
    let noteID: UUID
    let title: String
    let expiresAt: Date
}

struct AppFeedbackOverlay: View {
    @EnvironmentObject private var store: VaultStore
    @AppStorage("reduceMotion") private var reduceMotion = false

    var body: some View {
        ZStack {
            if let feedback = store.feedback {
                HStack(spacing: 10) {
                    if feedback.kind == .progress {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: feedback.kind.systemImage).foregroundStyle(feedback.kind.tint)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feedback.title).font(.callout.weight(.semibold))
                        if let detail = feedback.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                }
                .padding(11)
                .frame(maxWidth: 460)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(feedback.kind.tint.opacity(0.28)) }
                .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(16)
                .allowsHitTesting(false)
            }
            if let pending = store.pendingNoteDeletion {
                HStack(spacing: 12) {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("笔记已删除").font(.callout.weight(.semibold))
                        Text(pending.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Button("撤销") { store.undoPendingNoteDeletion() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: 440)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12)) }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(16)
            }
        }
        .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: store.feedback)
        .animation(MotionStyle.animation(reduceMotion: reduceMotion), value: store.pendingNoteDeletion)
    }
}
