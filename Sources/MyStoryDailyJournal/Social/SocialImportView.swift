import SwiftUI
import SwiftData

/// Bringing an Instagram export into the journal.
///
/// The archive arrives as a `.zip`. iOS has no public API for unzipping one,
/// and pulling in a third-party archiver to save a long-press is a poor
/// trade — so this asks for the *unzipped* folder and says plainly how to
/// get one. Files can uncompress a zip in place, which makes this two taps
/// rather than a dependency.
struct SocialImportView: View {
    @Environment(\.modelContext) private var context

    @State private var isChoosingFolder = false
    @State private var isImporting = false
    @State private var summary: SocialArchiveImporter.Summary?
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Text("Instagram will send you everything you have posted. Importing it gives the journal years it was never running for — what you said, when, and where.")
                    .font(.callout)
            }

            Section("How to get your archive") {
                stepRow(1, "In Instagram, open Settings → Accounts Center → Your information and permissions → Download your information.")
                stepRow(2, "Ask for your own account, all time, and choose **JSON** — not HTML. HTML cannot be read.")
                stepRow(3, "Instagram emails a link, usually within a few hours. Save the .zip to Files.")
                stepRow(4, "Long-press the .zip in Files and tap Uncompress, then choose that folder below.")
            }

            Section {
                Button {
                    isChoosingFolder = true
                } label: {
                    if isImporting {
                        HStack {
                            ProgressView()
                            Text("Reading your archive…").padding(.leading, 8)
                        }
                    } else {
                        Text("Choose the unzipped folder")
                    }
                }
                .disabled(isImporting)
            } footer: {
                Text("Read on this phone. Nothing is uploaded, and the photos and videos in the archive are counted, never copied.")
            }

            if let summary {
                Section("Imported") {
                    LabeledContent("Posts found", value: "\(summary.read)")
                    LabeledContent("Added", value: "\(summary.imported)")
                    if summary.skipped > 0 {
                        LabeledContent("Already here", value: "\(summary.skipped)")
                    }
                    if summary.daysCreated > 0 {
                        LabeledContent("New days", value: "\(summary.daysCreated)")
                    }
                    if summary.isEmpty {
                        Text("No posts were found in that folder. Check that it's the unzipped archive and that you asked Instagram for JSON rather than HTML.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let failure {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }

            Section {
                Button("Remove imported Instagram posts", role: .destructive) {
                    SocialArchiveImporter.forget(network: InstagramArchive.networkName, in: context)
                    summary = nil
                }
            } footer: {
                Text("Removes the posts. Days that already have entries keep them.")
            }
        }
        .navigationTitle("Instagram")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                load(from: url)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text(.init(text)).font(.callout)
        }
    }

    /// The picker's URL is only guaranteed to be reachable inside its own
    /// security scope, so the read happens here rather than being deferred.
    private func load(from url: URL) {
        failure = nil
        isImporting = true

        guard url.startAccessingSecurityScopedResource() else {
            failure = "Couldn't open that folder."
            isImporting = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let entries = InstagramArchive.entries(in: url)
        summary = SocialArchiveImporter.ingest(entries, in: context)
        isImporting = false
    }
}
