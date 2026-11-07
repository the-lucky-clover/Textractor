import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum MobileDecor {
    static let green = Color(red: 0.43, green: 0.71, blue: 0.18)
    static let background = Color(red: 0.05, green: 0.063, blue: 0.043)
}

@main
struct TextractorMobileApp: App {
    @StateObject private var store: ConversationStore
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            _store = StateObject(wrappedValue: ConversationStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("UITest-\(UUID().uuidString)")))
        } else { _store = StateObject(wrappedValue: ConversationStore()) }
        #else
        _store = StateObject(wrappedValue: ConversationStore())
        #endif
    }
    var body: some Scene {
        WindowGroup { MobileRootView().environmentObject(store).tint(MobileDecor.green).preferredColorScheme(.dark) }
    }
}

struct MobileRootView: View {
    @EnvironmentObject var store: ConversationStore
    @AppStorage("mobile.onboardingComplete") private var completed = false
    @State private var tour = false
    var body: some View {
        TabView {
            ScreenshotImportView().tabItem { Label("Sources", systemImage: "photo.stack") }
            TranscriptReviewView().tabItem { Label("Review", systemImage: "text.bubble") }
            ConversationSearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            MobileSettingsView(replay: { tour = true }).tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear { if !completed { tour = true } }
        .sheet(isPresented: $tour, onDismiss: { completed = true }) {
            MobileOnboardingView { completed = true; tour = false }
        }
        .alert("Textractor Pro", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct ScreenshotImportView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var selection: [PhotosPickerItem] = []
    @State private var files = false
    @State private var selectedSource: SourceScreenshot?
    @State private var busy = false
    @State private var progress = 0
    @State private var total = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Capture the context.", systemImage: "text.viewfinder").font(.title2.bold())
                        Text("Import screenshots in reading order. Textractor keeps the supplied images and extracts English (US) text on this device.")
                            .foregroundStyle(.secondary)
                        Text("For Messages, take overlapping screenshots yourself. Review OCR blocks, dates, speakers and overlap before export.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    PhotosPicker(selection: $selection, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
                        Label("Choose screenshots", systemImage: "photo.on.rectangle.angled")
                    }.disabled(busy || store.loadFailed).accessibilityIdentifier("mobile.import.photos")
                    Button { files = true } label: { Label("Import image files", systemImage: "folder") }
                        .disabled(busy || store.loadFailed)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                        Button("Load test screenshots") { importFixture() }.accessibilityIdentifier("mobile.fixture")
                    }
                    #endif
                }
                if busy {
                    Section {
                        ProgressView(value: Double(progress), total: Double(max(total, 1)))
                        Text("\(progress) of \(total) imported").monospacedDigit()
                        Text(store.importStatus).font(.caption)
                        Button("Cancel remaining imports", role: .cancel) { task?.cancel() }
                    }
                }
                Section("Originals · \(store.archive.sources.count) / 50") {
                    ForEach(store.archive.sources) { source in
                        Button { selectedSource = source } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.filename).foregroundStyle(.primary)
                                Text("\(store.archive.blocks.filter { $0.sourceID == source.id }.count) OCR blocks · imported \(source.importedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if store.archive.sources.filter({ $0.sha256 == source.sha256 }).count > 1 {
                                    Label("Identical image also imported", systemImage: "doc.on.doc").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }.onMove { store.moveSources(from: $0, to: $1) }
                }
            }
            .navigationTitle("Textractor Pro")
            .toolbar { EditButton().disabled(busy) }
            .sheet(item: $selectedSource) { SourceScreenshotView(source: $0) }
            .fileImporter(isPresented: $files, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                busy = true; total = items.count; progress = 0
                task = Task {
                    defer { busy = false; selection = []; task = nil }
                    for (index, item) in items.enumerated() {
                        do {
                            try Task.checkCancellation()
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw ConversationError.invalidImage }
                            try await store.importImage(data, name: "Screenshot \(store.archive.sources.count + 1)")
                            progress += 1
                        } catch is CancellationError { break }
                        catch { store.error = "Screenshot \(index + 1): \(error.localizedDescription)"; break }
                    }
                }
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        busy = true; total = urls.count; progress = 0
        task = Task {
            defer { busy = false; task = nil }
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    try Task.checkCancellation()
                    let data = try Data(contentsOf: url)
                    try await store.importImage(data, name: url.lastPathComponent)
                    progress += 1
                } catch is CancellationError { break }
                catch { store.error = "\(url.lastPathComponent): \(error.localizedDescription)"; break }
            }
        }
    }
    #if DEBUG
    private func importFixture() {
        busy = true; total = 1; progress = 0
        task = Task {
            defer { busy = false; task = nil }
            do { try await store.importImage(MobileFixture.image(), name: "Synthetic conversation.png"); progress = 1 }
            catch { store.error = error.localizedDescription }
        }
    }
    #endif
}

struct MobileSettingsView: View {
    @EnvironmentObject var store: ConversationStore
    var replay: () -> Void
    @AppStorage("mobile.includeTimestamps") private var timestamps = true
    @State private var export = false
    @State private var title = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Recognition") {
                    LabeledContent("Default language", value: "English (US)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Default recognition language")
                        .accessibilityValue("English (US)")
                        .accessibilityIdentifier("mobile.language")
                    Text("Recognition runs on this device using en-US.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Packet") {
                    TextField("Packet title", text: $title).onSubmit { store.rename(title) }
                    Button("Save title") { store.rename(title) }
                    Toggle("Include transcript timestamps", isOn: $timestamps)
                    Text("Dates are included only when visible in the screenshot or explicitly entered during review. Imported-at dates are tracked separately.").font(.caption)
                    Button("Prepare print packet") { export = true }.disabled(store.archive.sources.isEmpty)
                }
                Section("Help") {
                    Button("Replay welcome tour", action: replay).accessibilityIdentifier("mobile.onboarding.replay")
                    Text("Message layout is a reconstruction. OCR may misread text, timestamps or order. Compare with Sources; mark corrections and exclusions during review.").font(.callout)
                }
            }
            .navigationTitle("Settings").onAppear { title = store.archive.title }
            .sheet(isPresented: $export) { PacketExportView() }
        }
    }
}

struct MobileOnboardingView: View {
    var finish: () -> Void
    @State private var step = 0
    private let titles = ["Bring the screenshots.", "Review every detail.", "Print a clear record."]
    private let text = [
        "Select overlapping screenshots in reading order. English (US) is the default. Your imported images are retained separately from extracted text.",
        "OCR blocks are not verified messages. Check text and visible timestamps, assign speakers, and confirm overlap suggestions. Repeated messages are retained until you choose an exclusion.",
        "Create a numbered US Letter PDF with black text on white pages. Choose transcript or reconstructed message layout. Optional source pages and full audit JSON retain source content. Replay this tour in Settings."
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("Textractor Pro").font(.title2.bold()); Spacer(); Text("\(step + 1) of 3").monospacedDigit() }
            ProgressView(value: Double(step + 1), total: 3)
            Image(systemName: ["photo.stack", "checkmark.bubble", "printer"][step]).font(.system(size: 52)).foregroundStyle(MobileDecor.green)
            Text(titles[step]).font(.largeTitle.bold())
            ScrollView { Text(text[step]).font(.title3).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Skip tour", action: finish).accessibilityIdentifier("mobile.onboarding.skip")
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == 2 ? "Done" : "Continue") { if step == 2 { finish() } else { step += 1 } }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("mobile.onboarding.next")
            }
        }.padding(24).background(MobileDecor.background)
    }
}

#if DEBUG
enum MobileFixture {
    @MainActor static func image() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).pngData { context in
            UIColor.white.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            let values = ["Today 9:41 AM", "Please bring the blue folder.", "I will arrive at the library at noon.", "Thank you for confirming."]
            for (index, value) in values.enumerated() {
                (value as NSString).draw(at: CGPoint(x: 55, y: 120 + index * 170), withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black])
            }
        }
    }
}
#endif
