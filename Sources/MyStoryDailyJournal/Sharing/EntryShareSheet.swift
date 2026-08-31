import SwiftUI
import SwiftData

/// The one screen where a private journal becomes public, so it shows the
/// writer exactly what will leave the phone and lets them take any of it
/// out first.
///
/// Everything here works on a copy. Redacting a name, trimming the text,
/// dropping the date — none of it touches the stored entry.
struct EntryShareSheet: View {
    let record: DayRecord

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private enum Format: String, CaseIterable, Identifiable {
        case text = "Text"
        case card = "Card"
        var id: String { rawValue }
    }

    @State private var format: Format = .text
    @State private var includeDate = true
    @State private var redacted: Set<String> = []
    @State private var edited: String
    @State private var cardURL: URL?
    @State private var renderError: String?

    init(record: DayRecord) {
        self.record = record
        _edited = State(initialValue: record.bodyText)
    }

    private var terms: [ShareableEntry.SensitiveTerm] {
        ShareableEntry.sensitiveTerms(in: record, text: edited)
    }

    /// Exactly what goes out — the same string the share sheet receives.
    private var shareText: String {
        ShareableEntry.text(
            body: edited,
            date: includeDate ? record.date : nil,
            redacting: terms.filter { redacted.contains($0.id) },
            timeZoneIdentifier: record.timeZoneIdentifier
        )
    }

    private var dateLine: String? {
        guard includeDate else { return nil }
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
        style.timeZone = TimeZone(identifier: record.timeZoneIdentifier) ?? .current
        return record.date.formatted(style)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include the date", isOn: $includeDate)
                }

                if !terms.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(terms) { term in
                                    redactionChip(for: term)
                                }
                            }
                        }
                    } header: {
                        Text("Names in this entry")
                    } footer: {
                        Text("Tap a name to take it out of the shared copy. Your entry keeps it.")
                    }
                }

                Section {
                    TextEditor(text: $edited)
                        .frame(minHeight: 160)
                        .font(.system(.body, design: .serif))
                } header: {
                    Text("What you're sharing")
                } footer: {
                    if format == .card, edited.count > EntryCard.maximumCharacters {
                        Text("The card shows the first \(EntryCard.maximumCharacters) characters. Share as text to send all of it.")
                    }
                }

                if format == .card {
                    Section {
                        preview
                    }
                }
            }
            .navigationTitle("Share this day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    shareButton
                }
            }
            .alert(
                "Couldn't make the card",
                isPresented: Binding(get: { renderError != nil }, set: { _ in renderError = nil })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(renderError ?? "")
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        switch format {
        case .text:
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        case .card:
            if let cardURL {
                ShareLink(item: cardURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                Button("Share") { renderCard() }
            }
        }
    }

    /// The card as it will actually look, scaled down — a picture of the
    /// thing being shared beats a description of it.
    @ViewBuilder
    private var preview: some View {
        EntryCard(dateLine: dateLine, body_: shareBodyForCard, accent: settings.theme.accent)
            .scaleEffect(0.28, anchor: .topLeading)
            .frame(
                width: EntryCard.size.width * 0.28,
                height: EntryCard.size.height * 0.28
            )
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.25))
            }
            .padding(.vertical, 8)
    }

    /// The card carries the date in its own header, so the body it renders
    /// is the entry alone.
    private var shareBodyForCard: String {
        ShareableEntry.text(
            body: edited,
            redacting: terms.filter { redacted.contains($0.id) },
            timeZoneIdentifier: record.timeZoneIdentifier
        )
    }

    private func redactionChip(for term: ShareableEntry.SensitiveTerm) -> some View {
        let isRedacted = redacted.contains(term.id)
        return Button {
            if isRedacted {
                redacted.remove(term.id)
            } else {
                redacted.insert(term.id)
            }
            cardURL = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isRedacted ? "eye.slash" : "eye")
                Text(isRedacted ? term.replacement : term.term)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isRedacted ? Color.secondary.opacity(0.25) : Color.accentColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func renderCard() {
        do {
            cardURL = try EntryCardRenderer.pngURL(
                dateLine: dateLine,
                body: shareBodyForCard,
                accent: settings.theme.accent,
                fileName: "my-story-\(record.date.formatted(.iso8601.year().month().day()))"
            )
        } catch {
            renderError = "Try sharing as text instead."
        }
    }
}
