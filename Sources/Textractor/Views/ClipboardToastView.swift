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

    /// Two-way binding that funnels the weirdness slider through `AppState`,
    /// which writes back to `SettingsStore` (the real source of truth).
    private var weirdnessBinding: Binding<Double> {
        Binding(
            get: { appState.settings.weirdness },
            set: { newValue in
                appState.updateSettings { $0.weirdness = newValue }
            }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            
            // MARK: - Screen Recording permission denial (privacy reassurance)
            if toast.screenRecordingDenied {
                screenPermissionContent
            } else if toast.kind == .failure && toast.recoveryImagePath != nil {
                englishFailureContent
            } else if !toast.bodyText.isEmpty {
                Text(toast.bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let analysis = toast.analysis {
                analysisRow(analysis)
            }
            
            // MARK: - Action Row
            Divider().background(Color.secondary.opacity(0.3))
            actionRow
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BreakingDad.greenBlack)
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
                if toast.kind == .success {
                    AnimatedCheckmark(size: 34, lineWidth: 3.5)
                } else {
                    Circle().fill(borderColor.opacity(0.16)).frame(width: 32, height: 32)
                    if toast.screenRecordingDenied {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16, weight: .black))
                    } else if toast.kind == .failure && toast.recoveryImagePath != nil {
                        // Recovery failure icon
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(borderColor)
                            .font(.system(size: 16, weight: .black))
                    } else if toast.kind == .failure {
                        Image(systemName: toast.kind == .failure ? "exclamationmark.triangle.fill"
                                                                : "doc.on.clipboard.fill")
                            .foregroundStyle(borderColor)
                            .font(.system(size: 16, weight: .black))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(toast.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let cap = toast.capture {
                    Text(String(format: T.s("toast.captured_at"), cap.capturedAt.formatted(date: .omitted, time: .standard)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let reason = toast.failureReason {
                    Text(String(format: T.s("toast.failure_reason"), reason))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }
            Spacer()
        }
    }

    // MARK: - English Detection Failure Content

    @ViewBuilder private var englishFailureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image preview
            if let path = toast.recoveryImagePath {
                HStack(spacing: 12) {
                    ImagePreview(path: path)
                        .frame(width: 80, height: 60)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T.s("toast.english_fail_title"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(T.s("toast.english_fail_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Weirdness slider
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: T.s("toast.weirdness"), appState.settings.weirdness))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(
                    value: weirdnessBinding,
                    in: 0...100,
                    step: 5
                )
                .frame(maxWidth: 200)
            }
            
            // PII status indicator
            if toast.piiWasRedacted {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(BreakingDad.cautionOrange)
                    Text(String(format: T.s("toast.pii_redacted"), toast.piiRedactionsApplied))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Screen Recording permission denial content

    @ViewBuilder private var screenPermissionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(toast.bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Image Preview View

    struct ImagePreview: NSViewRepresentable {
        let path: String
        
        func makeNSView(context: Context) -> NSImageView {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.animates = true
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 4
            return imageView
        }
        
        func updateNSView(_ nsView: NSImageView, context: Context) {
            let url = URL(fileURLWithPath: path)
            if let image = NSImage(contentsOf: url) {
                nsView.image = image
            } else {
                nsView.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            }
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
            case .positive: return BreakingDad.toxicGreen
            case .negative: return BreakingDad.rust
            case .neutral:  return BreakingDad.chalk
            case .mixed:    return BreakingDad.methBlue
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

    // MARK: - Share + Copy (normal mode)

    @ViewBuilder private var actionRow: some View {
        // Recovery failure actions
        if toast.kind == .failure && toast.recoveryImagePath != nil {
            HStack(spacing: 10) {
                Button(action: { toast.tryAgain?() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text(T.s("toast.try_again"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BreakingDad.toxicGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(BreakingDad.toxicGreen.opacity(0.10))
                            .overlay(Capsule().stroke(BreakingDad.toxicGreen.opacity(0.5), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: { toast.revealRecovery?() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(T.s("toast.reveal"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.10))
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: { toast.cancel?() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text(T.s("toast.cancel"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.10))
                            .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.top, 2)
        } else {
            // Normal success/failure action row
            HStack(spacing: 10) {
                Button(action: onCopy) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc.fill")
                        Text(T.s("toast.copy"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BreakingDad.toxicGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(BreakingDad.toxicGreen.opacity(0.10))
                            .overlay(Capsule().stroke(BreakingDad.toxicGreen.opacity(0.5), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                
                if toast.kind == .success {
                    shareChip(T.s("toast.share_mail"), icon: "envelope.fill", tint: .blue) { onShare(.email) }
                    shareChip(T.s("toast.share_message"), icon: "message.fill", tint: .green) { onShare(.message) }
                    shareChip(T.s("toast.share_airdrop"), icon: "antenna.radiowaves.left.and.right", tint: .orange) { onShare(.airDrop) }
                }

                if toast.screenRecordingDenied {
                    Button(action: { toast.openSettings?() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape.fill")
                            Text(T.s("toast.open_settings"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BreakingDad.toxicGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(BreakingDad.toxicGreen.opacity(0.10))
                                .overlay(Capsule().stroke(BreakingDad.toxicGreen.opacity(0.5), lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.top, 2)
        }
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
        case .success: return BreakingDad.toxicGreen
        case .failure: return BreakingDad.cautionOrange
        case .info:    return BreakingDad.methBlue
        }
    }
}
