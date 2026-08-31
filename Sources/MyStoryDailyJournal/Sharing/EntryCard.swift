import SwiftUI

/// A day rendered as an image worth posting: the date, the words, and
/// nothing else. No app chrome, no watermark over the writing, no counts
/// or streaks — what gets shared is the entry, not the product.
struct EntryCard: View {
    let dateLine: String?
    let body_: String
    let accent: Color

    /// Portrait, at the aspect ratio every social app crops to least.
    static let size = CGSize(width: 1080, height: 1350)

    /// Longer than this and the card becomes unreadable at phone size, so
    /// the writer is told it's an excerpt rather than being given a wall.
    static let maximumCharacters = 900

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            if let dateLine {
                VStack(alignment: .leading, spacing: 16) {
                    Text(dateLine)
                        .font(.system(size: 34, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(accent)
                        .frame(width: 96, height: 4)
                }
            }

            Text(excerpt)
                .font(.system(size: 46, weight: .regular, design: .serif))
                .lineSpacing(14)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(88)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground))
    }

    private var excerpt: String {
        let trimmed = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > Self.maximumCharacters else { return trimmed }
        return String(trimmed.prefix(Self.maximumCharacters)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Turns the card into a PNG on disk for the share sheet. A file rather
/// than an in-memory image because that's what every target — Messages,
/// Instagram, Files — accepts without translation.
@MainActor
enum EntryCardRenderer {
    static func pngURL(dateLine: String?, body: String, accent: Color, fileName: String = "entry") throws -> URL {
        let renderer = ImageRenderer(content: EntryCard(dateLine: dateLine, body_: body, accent: accent))
        renderer.scale = 1

        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
