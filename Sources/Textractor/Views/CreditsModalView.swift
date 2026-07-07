import SwiftUI
import AppKit

/// "Made with <3 by Lucky Clover" modal.
///
/// Clicking the *Lucky Clover* hyperlink hands off to the system browser
/// (which opens `https://soundcloud.com/lucky-clover` in a new tab). The
/// plain OK button dismisses the sheet.
struct CreditsModalView: View {

    @Environment(\.dismiss) private var dismiss

    private let soundcloudURL = URL(string: "https://soundcloud.com/lucky-clover")!

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Textractor")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Built with care")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            Divider()

            HStack(spacing: 6) {
                Text("Made with")
                    .font(.system(size: 22, weight: .regular))
                Text("♥")
                    .foregroundStyle(Color.red.opacity(0.85))
                Text("by")
                    .font(.system(size: 22, weight: .regular))
                Button {
                    SoundManager.playClick()
                    NSWorkspace.shared.open(soundcloudURL)
                } label: {
                    Text("Lucky Clover")
                        .font(.system(size: 22, weight: .semibold))
                        .underline()
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Open soundcloud.com/lucky-clover")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)

            HStack {
                Spacer()
                Button("OK") {
                    SoundManager.playClick()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    CreditsModalView()
}
