import SwiftUI

struct PaletteStep: View {
    @EnvironmentObject private var settings: SettingsStore

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        VStack(spacing: 24) {
            Text("Pick an accent color")
                .font(.title3)
                .padding(.top, 40)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Theme.allCases) { theme in
                    Button {
                        settings.theme = theme
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if settings.theme == theme {
                                        Circle().strokeBorder(Color.primary, lineWidth: 2)
                                    }
                                }
                            Text(theme.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}
