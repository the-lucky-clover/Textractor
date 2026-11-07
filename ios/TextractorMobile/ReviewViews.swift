import SwiftUI
import UIKit

struct TranscriptReviewView: View {
    @EnvironmentObject var store: ConversationStore
    @AppStorage("mobile.includeTimestamps") private var timestamps = true
    @State private var showExcluded = false
    @State private var editing: TranscriptBlock?
    @State private var export = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Reconstructed from screenshots").font(.headline)
                    Text("Reading order and timestamp labels are OCR suggestions. Tap a block to correct text, assign a speaker, or mark interface text. Direction stays unassigned until you choose it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("Show transcript timestamps", isOn: $timestamps)
                    Toggle("Show excluded blocks", isOn: $showExcluded)
                    NavigationLink { OverlapReviewView() } label: {
                        Label("Review overlap suggestions (\(ConversationLogic.overlaps(in: store.archive).count))", systemImage: "square.on.square")
                    }
                }
                Section("\(store.archive.blocks.count) OCR blocks") {
                    ForEach(store.archive.blocks.filter { (showExcluded || !$0.excluded) && (timestamps || $0.kind != .timestamp) }) { block in
                        Button { editing = block } label: { MessageBlockView(block: block) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mobile.block.\(block.id.uuidString)")
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar { Button("Export") { export = true }.disabled(store.archive.sources.isEmpty).accessibilityIdentifier("mobile.export") }
            .sheet(item: $editing) { BlockEditorView(block: $0) }
            .sheet(isPresented: $export) { PacketExportView() }
        }
    }
}

struct MessageBlockView: View {
    let block: TranscriptBlock
    var body: some View {
        HStack {
            if block.side == .outgoing { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(block.kind == .timestamp ? "Visible timestamp · OCR" : (block.speaker.isEmpty ? "Unassigned speaker" : block.speaker))
                        .font(.caption.bold())
                    Spacer(minLength: 0)
                    if block.isEdited { Text("Edited").font(.caption).foregroundStyle(.orange) }
                }
                Text(block.text).textSelection(.enabled)
                if !block.userTimestamp.isEmpty { Text("User timestamp: \(block.userTimestamp)").font(.caption) }
                if block.excluded { Label("Excluded from transcript", systemImage: "eye.slash").font(.caption).foregroundStyle(.orange) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(block.side == .outgoing ? MobileDecor.green.opacity(0.18) : Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MobileDecor.green.opacity(0.25)))
            if block.side != .outgoing { Spacer(minLength: 24) }
        }.padding(.vertical, 4)
    }
}

struct BlockEditorView: View {
    @EnvironmentObject var store: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State var block: TranscriptBlock
    @State private var edited = ""
    @State private var showSource = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Source OCR · retained unchanged") {
                    Text(block.originalText).textSelection(.enabled)
                    Button("Compare with original screenshot") { showSource = true }
                }
                Section("Reviewed text") {
                    TextEditor(text: $edited).frame(minHeight: 130).accessibilityIdentifier("mobile.editor.text")
                    if edited.count > 20000 { Text("Keep each block under 20,000 characters.").foregroundStyle(.orange) }
                    Picker("Block type", selection: $block.kind) {
                        Text("Message text").tag(TextKind.message)
                        Text("Visible timestamp").tag(TextKind.timestamp)
                        Text("Interface / header").tag(TextKind.interface)
                    }
                    Text("Timestamp detection is a suggestion; review this classification.").font(.caption)
                }
                Section("User-supplied context") {
                    TextField("Speaker (optional)", text: $block.speaker)
                    Picker("Message direction", selection: $block.side) {
                        Text("Unassigned").tag(MessageSide.unassigned)
                        Text("Incoming").tag(MessageSide.incoming)
                        Text("Outgoing").tag(MessageSide.outgoing)
                    }
                    TextField("Timestamp you supply (optional)", text: $block.userTimestamp)
                    Text("A manually entered timestamp is labeled as user supplied. It does not replace or establish a source date.").font(.caption)
                }
                Section("Presentation") {
                    Toggle("Exclude from transcript", isOn: $block.excluded)
                    if block.excluded { TextField("Reason for exclusion", text: $block.exclusionReason) }
                    Text("The source image and original OCR remain in the packet. Edits and exclusions are logged.").font(.caption)
                }
            }
            .navigationTitle("Review block")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        block.editedText = edited == block.originalText ? nil : edited
                        if store.update(block) { dismiss() }
                    }.disabled(edited.count > 20000 || (block.excluded && block.exclusionReason.trimmingCharacters(in: .whitespaces).isEmpty))
                    .accessibilityIdentifier("mobile.editor.save")
                }
            }
            .onAppear { edited = block.text }
            .sheet(isPresented: $showSource) {
                if let source = store.archive.sources.first(where: { $0.id == block.sourceID }) {
                    SourceScreenshotView(source: source, selectedRect: block.rect)
                }
            }
        }
    }
}

struct SourceScreenshotView: View {
    @EnvironmentObject var store: ConversationStore
    @Environment(\.dismiss) private var dismiss
    let source: SourceScreenshot
    var selectedRect: CGRect?
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                            .overlay {
                                if let rect = selectedRect {
                                    GeometryReader { geo in
                                        Rectangle().stroke(.orange, lineWidth: 2)
                                            .frame(width: rect.width * geo.size.width, height: rect.height * geo.size.height)
                                            .position(x: rect.midX * geo.size.width, y: (1 - rect.midY) * geo.size.height)
                                    }
                                }
                            }
                        Text(selectedRect == nil ? "Original supplied image · checksum verified" : "Original supplied image · selected OCR region outlined")
                            .font(.caption)
                    }
                    if let error { Text(error).foregroundStyle(.orange) }
                    Text("Imported \(source.importedAt.formatted()) · not a message timestamp").font(.caption)
                    Text("SHA-256\n\(source.sha256)").font(.caption.monospaced()).textSelection(.enabled)
                }.padding()
            }
            .navigationTitle(source.filename).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                do {
                    let data = try store.originalData(source)
                    guard let raster = ConversationStore.thumbnail(data: data) else { throw ConversationError.invalidImage }
                    image = UIImage(cgImage: raster)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct OverlapReviewView: View {
    @EnvironmentObject var store: ConversationStore
    var body: some View {
        List {
            Text("Suggestions compare adjacent screenshot endings and beginnings. Nothing is removed automatically. Repeated short replies alone are not enough to propose an overlap.").font(.callout)
            let proposals = ConversationLogic.overlaps(in: store.archive)
            if proposals.isEmpty { Text("No pending overlap suggestions.").foregroundStyle(.secondary) }
            ForEach(proposals) { proposal in
                Section {
                    Text("\(Int(proposal.similarity * 100))% text similarity · heuristic").font(.headline)
                    Text("Earlier screenshot").font(.caption.bold())
                    Text(store.archive.blocks.filter { proposal.earlierIDs.contains($0.id) }.map(\.text).joined(separator: "\n"))
                    Text("Later screenshot").font(.caption.bold())
                    Text(store.archive.blocks.filter { proposal.laterIDs.contains($0.id) }.map(\.text).joined(separator: "\n"))
                    Button("Keep both regions") { store.keepOverlap(proposal) }
                    Button("Confirm overlap; exclude later region") { store.excludeOverlap(proposal) }
                    Text("Exclusion is reversible in Review → Show excluded blocks. Original images remain unchanged.").font(.caption)
                }
            }
        }.navigationTitle("Overlap review")
    }
}

struct ConversationSearchView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var query = ""
    @State private var mode = ConversationSearchMode.fuzzy
    @State private var result = ConversationSearchResult(hits: [], note: nil)
    @State private var editing: TranscriptBlock?
    @State private var engine = ConversationSearch()
    @State private var searching = false
    var body: some View {
        NavigationStack {
            List {
                Picker("Search mode", selection: $mode) { ForEach(ConversationSearchMode.allCases) { Text($0.rawValue).tag($0) } }
                if searching { ProgressView("Searching on this device…") }
                if let note = result.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                Text("\(result.hits.count) matching blocks").font(.caption).accessibilityIdentifier("mobile.search.count")
                ForEach(result.hits) { hit in
                    Button { editing = hit.block } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(hit.block.text).foregroundStyle(.primary)
                            Text("\(mode == .exact ? "Exact text" : "Rank score") · \(Int(hit.score * 100)) · tap to inspect source")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Search extracted text")
            .task(id: query + mode.rawValue + String(store.archive.changes.count)) {
                searching = true
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                let found = await engine.search(query, mode: mode, blocks: store.archive.blocks)
                guard !Task.isCancelled else { return }
                result = found; searching = false
            }
            .sheet(item: $editing) { BlockEditorView(block: $0) }
        }
    }
}

struct PacketExportView: View {
    @EnvironmentObject var store: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mobile.includeTimestamps") private var timestamps = true
    @State private var options = PacketOptions()
    @State private var share: ShareFiles?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Print presentation") {
                    Picker("Layout", selection: $options.layout) { ForEach(PacketLayout.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Include transcript timestamps", isOn: $options.includeTimestamps)
                    Toggle("Append grayscale source pages", isOn: $options.includeSourcePages)
                    Toggle("Include full source text and edit history JSON", isOn: $options.includeAuditJSON)
                    Text("Timestamp visibility affects the transcript only. Source pages and full audit JSON retain source text, including timestamps and excluded blocks.").font(.caption)
                }
                Section("US Letter · black and white") {
                    Text("Black text, white backgrounds, outlined message bubbles, and Page X of Y numbering. Reconstructed layouts and user edits are labeled. Original images are retained separately.")
                    Text("This is a reviewable export, not a certification of authenticity or court admissibility.").font(.caption).foregroundStyle(.secondary)
                    Button {
                        busy = true
                        Task { @MainActor in
                            await Task.yield()
                            defer { busy = false }
                            do { share = ShareFiles(urls: try PrintPacketRenderer.export(store: store, options: options)) }
                            catch { store.error = error.localizedDescription }
                        }
                    } label: {
                        if busy { ProgressView("Preparing packet…") } else { Label("Create PDF packet", systemImage: "doc.richtext") }
                    }.disabled(busy || store.archive.sources.isEmpty).accessibilityIdentifier("mobile.pdf.create")
                }
            }
            .navigationTitle("Print packet")
            .toolbar { Button("Done") { dismiss() }.disabled(busy) }
            .onAppear { options.includeTimestamps = timestamps }
            .sheet(item: $share) { ActivitySheet(urls: $0.urls) }
        }
    }
}
struct ShareFiles: Identifiable { let id = UUID(); var urls: [URL] }
struct ActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
