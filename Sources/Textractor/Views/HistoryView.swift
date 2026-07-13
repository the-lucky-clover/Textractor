import SwiftUI
import AppKit

/// The main "History" window. Shows a grid of past captures as screenshot
/// thumbnails with their extracted text. On open the cards stagger in; on close
/// they stagger out before the window actually dismisses.
public struct HistoryView: View {

    @StateObject private var store = HistoryStore.shared

    @State private var appeared = false
    @State private var closing = false

    /// Called once the closing animation has finished; the window controller
    /// uses it to actually close the window.
    var onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 460, idealHeight: 560)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("History")
                .font(.headline)
            if !store.records.isEmpty {
                Text("\(store.records.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
            if !store.records.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.clear() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear history")
            }
            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(12)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if store.records.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text("No captures yet")
                    .foregroundStyle(.secondary)
                Text("Captured text and screenshots will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(store.records.enumerated()), id: \.element.id) { index, record in
                        HistoryCard(
                            record: record,
                            index: index,
                            appeared: appeared,
                            closing: closing,
                            onTap: {
                                ClipboardService.shared.copy(record.textPreview, attributed: nil, plainTextOnly: true)
                                SoundManager.playCaptureComplete()
                            },
                            onDelete: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.delete(record) }
                            }
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Closing

    private func requestClose() {
        closing = true
        let total = Double(min(store.records.count, 40)) * 0.025 + 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { onClose() }
    }
}

// MARK: - Card

private struct HistoryCard: View {

    let record: HistoryRecord
    let index: Int
    let appeared: Bool
    let closing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    /// Single animation token so appear/closing share one `.animation` modifier
    /// (avoids conflicting per-property animations).
    private var animKey: Int { (appeared ? 1 : 0) + (closing ? 2 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: CaptureMode(rawValue: record.mode.rawValue)?.symbolName ?? "doc")
                    .foregroundStyle(BreakingDad.toxicGreen)
                Text(record.capturedAt, style: .date)
                Text(record.capturedAt, style: .time)
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(record.textPreview.isEmpty ? "(no text)" : record.textPreview)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovered ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hovered ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovered = $0 }
        .contextMenu { Button("Delete", action: onDelete) }
        .overlay(deleteButton, alignment: .topTrailing)
        .opacity(closing ? 0 : (appeared ? 1 : 0))
        .offset(y: closing ? 8 : (appeared ? 0 : 12))
        .scaleEffect(closing ? 0.96 : 1)
        .animation(.spring(response: 0.42, dampingFraction: 0.8).delay(Double(index) * 0.035), value: animKey)
    }

    @ViewBuilder private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background))
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1 : 0)
        .padding(6)
    }

}
