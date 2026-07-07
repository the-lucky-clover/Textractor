import SwiftUI

/// Animated clipboard confirmation toast with storage-decision chips +
/// quick-share chips (Mail / Messages / AirDrop).
public struct ClipboardToastView: View {

    @ObservedObject var appState: AppState
    let toast: ToastState

    var onShare: (ShareService.Provider) -> Void

    public init(
        appState: AppState,
        toast: ToastState,
        onShare: @escaping (ShareService.Provider) -> Void
    ) {
        self.appState = appState
        self.toast = toast
        self.onShare = onShare
    }

    @State private var appear: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !toast.bodyText.isEmpty {
                Text(toast.bodyText)
                    .font(NeonFont.roundedHeadline(13))
                    .foregroundStyle(NeonPalette.inkMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let analysis = toast.analysis {
                analysisRow(analysis)
            }
            if toast.storageQuestion != .none {
                Divider().background(NeonPalette.inkLow.opacity(0.3))
                storageActions
            } else {
                Divider().background(NeonPalette.inkLow.opacity(0.0))
                shareActions
            }
        }
        .padding(14)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1.6)
                .modifier(NeonGlow.outer(borderColor, radius: 18, opacity: 0.6))
        )
        .scaleEffect(appear ? 1.0 : 0.85)
        .opacity(appear ? 1.0 : 0)
        .onAppear {
            withAnimation(Motion.springTactile) {
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
                Image(systemName: toast.kind == .success ? "checkmark.seal.fill" : (toast.kind == .failure ? "exclamationmark.triangle.fill" : "doc.on.clipboard.fill"))
                    .foregroundStyle(borderColor)
                    .font(.system(size: 16, weight: .black))
                    .modifier(NeonGlow.outer(borderColor, radius: 10, opacity: 0.7))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(toast.headline)
                    .font(NeonFont.roundedHeadline(15))
                    .foregroundStyle(NeonPalette.inkHigh)
                if let cap = toast.capture {
                    Text("Captured at \(cap.capturedAt.formatted(date: .omitted, time: .standard))")
                        .font(NeonFont.mono(10))
                        .foregroundStyle(NeonPalette.inkLow)
                }
            }
            Spacer()
        }
    }

    // MARK: - Analysis chip

    @ViewBuilder private func analysisRow(_ analysis: AIInferenceService.Analysis) -> some View {
        HStack(spacing: 8) {
            sentimentChip(analysis.sentiment)
            if let lang = analysis.language {
                chip(systemImage: "character.book.closed", text: lang, tint: NeonPalette.holoViolet)
            }
            chip(systemImage: "number", text: "\(analysis.tokens) tokens", tint: NeonPalette.amberLaser)
            Spacer()
        }
        .font(NeonFont.monoCaps(10))
    }

    private func sentimentChip(_ s: AIInferenceService.Sentiment) -> some View {
        let tint: Color = {
            switch s {
            case .positive: return NeonPalette.acidLime
            case .negative: return NeonPalette.hazardRed
            case .neutral:  return NeonPalette.cyberCyan
            case .mixed:    return NeonPalette.holoViolet
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
                .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 0.8))
        )
    }

    // MARK: - Storage Actions

    @ViewBuilder private var storageActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save this screenshot?")
                .font(NeonFont.monoCaps(11))
                .foregroundStyle(NeonPalette.inkMid)
            HStack(spacing: 8) {
                storageButton("Save", icon: "tray.and.arrow.down.fill", tint: NeonPalette.acidLime) {
                    resolveStorage(.keepInDefaultFolder)
                }
                storageButton("Pick Where…", icon: "folder.badge.plus", tint: NeonPalette.cyberCyan) {
                    resolveStorage(.saveTo(pickerURL))
                }
                storageButton("Delete", icon: "trash.fill", tint: NeonPalette.hazardRed) {
                    resolveStorage(.delete)
                }
                if appState.settings.storageMode == .ask {
                    storageButton("Always Save", icon: "infinity.circle", tint: NeonPalette.magentaNeon) {
                        appState.updateSettings { $0.storageMode = .safe }
                        resolveStorage(.keepInDefaultFolder)
                    }
                }
            }
        }
    }

    private func resolveStorage(_ decision: StorageDecision) {
        // The pipeline attaches `toast.resolveStorage` (set by AppCoordinator);
        // when not in ask mode, the toast never shows the storage question, so
        // this path is unreachable.
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
            .font(NeonFont.monoCaps(11))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 0.8))
            )
            .modifier(NeonGlow.inner(tint, radius: 8, opacity: 0.45))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Share Actions

    @ViewBuilder private var shareActions: some View {
        HStack(spacing: 10) {
            shareChip("Mail", icon: "envelope.fill", tint: NeonPalette.magentaNeon) { onShare(.email) }
            shareChip("Message", icon: "message.fill", tint: NeonPalette.cyberCyan) { onShare(.message) }
            shareChip("AirDrop", icon: "antenna.radiowaves.left.and.right", tint: NeonPalette.acidLime) { onShare(.airDrop) }
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
            .font(NeonFont.monoCaps(11))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 0.8))
            )
            .modifier(NeonGlow.inner(tint, radius: 8, opacity: 0.45))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Border color

    private var borderColor: Color {
        switch toast.kind {
        case .success: return NeonPalette.cyberCyan
        case .failure: return NeonPalette.hazardRed
        case .info:    return NeonPalette.holoViolet
        }
    }
}
