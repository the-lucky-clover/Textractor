import SwiftUI
import AppKit

/// Animated clipboard-confirmation toast. Shows the extracted text preview,
/// AI analysis chips, and (in "ask" mode) save/delete decisions or quick-share
/// chips. Styled to match the menubar popover: native system chrome, plain
/// materials, semantic colours — no neon.
public struct ClipboardToastView: View {

    @ObservedObject var appState: AppState
    let toast: ToastState

    var onShare: (ShareService.Provider) -> Void
    var onCopy: () -> Void

    public init(
        appState: AppState,
        toast: ToastState,
        onShare: @escaping (ShareService.Provider) -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.appState = appState
        self.toast = toast
        self.onShare = onShare
        self.onCopy = onCopy
    }

    @State private var appear: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !toast.bodyText.isEmpty {
                Text(toast.bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let analysis = toast.analysis {
                analysisRow(analysis)
            }
            if toast.storageQuestion != .none {
                Divider().background(Color.secondary.opacity(0.3))
                storageActions
            } else {
                Divider().background(Color.secondary.opacity(0.3))
                actionRow
            }
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor.opacity(0.5), lineWidth: 1)
        )
        .scaleEffect(appear ? 1.0 : 0.9)
        .opacity(appear ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appear = true
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(borderColor.opacity(0.16)).frame(width: 32, height: 32)
                Image(systemName: toast.kind == .success ? "checkmark.seal.fill"
                                    : (toast.kind == .failure ? "exclamationmark.triangle.fill"
                                                               : "doc.on.clipboard.fill"))
                    .foregroundStyle(borderColor)
                    .font(.system(size: 16, weight: .black))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(toast.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let cap = toast.capture {
                    Text("Captured at \(cap.capturedAt.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Analysis chips

    @ViewBuilder private func analysisRow(_ analysis: AIInferenceService.Analysis) -> some View {
        HStack(spacing: 8) {
            sentimentChip(analysis.sentiment)
            if let lang = analysis.language {
                chip(systemImage: "character.book.closed", text: lang, tint: .purple)
            }
            chip(systemImage: "number", text: "\(analysis.tokens) tokens", tint: .orange)
            Spacer()
        }
        .font(.system(size: 10, weight: .semibold))
    }

    private func sentimentChip(_ s: AIInferenceService.Sentiment) -> some View {
        let tint: Color = {
            switch s {
            case .positive: return .green
            case .negative: return .red
            case .neutral:  return .accentColor
            case .mixed:    return .purple
            }
        }()
        return chip(systemImage: "waveform.path.ecg", text: s.label, tint: tint)
    }

    private func chip(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text.uppercased())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
                .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.8))
        )
    }

    // MARK: - Storage actions (ask mode)

    @ViewBuilder private var storageActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save this screenshot?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                storageButton("Save", icon: "tray.and.arrow.down.fill", tint: .green) {
                    resolveStorage(.keepInDefaultFolder)
                }
                storageButton("Pick Where…", icon: "folder.badge.plus", tint: .accentColor) {
                    resolveStorage(.saveTo(pickerURL))
                }
                storageButton("Delete", icon: "trash.fill", tint: .red) {
                    resolveStorage(.delete)
                }
                if appState.settings.storageMode == .ask {
                    storageButton("Always Save", icon: "infinity.circle", tint: .purple) {
                        appState.updateSettings { $0.storageMode = .safe }
                        resolveStorage(.keepInDefaultFolder)
                    }
                }
            }
        }
    }

    private func resolveStorage(_ decision: StorageDecision) {
        if let r = toast.resolveStorage {
            r(decision)
        }
    }

    private var pickerURL: URL {
        appState.settings.saveFolderPath
            .map(URL.init(fileURLWithPath:))
            ?? AppSettings.defaultSaveFolder()
    }

    private func storageButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Share + Copy (normal mode)

    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: onCopy) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.10))
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            shareChip("Mail", icon: "envelope.fill", tint: .blue) { onShare(.email) }
            shareChip("Message", icon: "message.fill", tint: .green) { onShare(.message) }
            shareChip("AirDrop", icon: "antenna.radiowaves.left.and.right", tint: .orange) { onShare(.airDrop) }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func shareChip(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Border color

    private var borderColor: Color {
        switch toast.kind {
        case .success: return .green
        case .failure: return .red
        case .info:    return .accentColor
        }
    }
}
