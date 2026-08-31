import SwiftUI
import SwiftData

/// §16: "Two views, one toggle, not two tabs." A segmented control switches
/// between the List and Month Grid, not separate tab bar items.
struct RootView: View {
    private enum Layout: String, CaseIterable {
        case list = "List"
        case month = "Month"
    }

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var quickCapture: QuickCaptureCoordinator
    @Environment(\.modelContext) private var context
    @State private var layout: Layout = .list
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                CloudStatusBanner()

                Picker("View", selection: $layout) {
                    ForEach(Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch layout {
                case .list:
                    DayListView()
                case .month:
                    MonthGridView()
                }
            }
            // Always reachable, over either layout: the app's own way of
            // asking who the people in this journal are.
            .overlay(alignment: .bottomTrailing) {
                FloatingPenButton()
            }
            .navigationTitle("My Story")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        quickCapture.isPresented = true
                    } label: {
                        Image(systemName: "bolt")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: DateUtilities.startOfDay(for: .now)) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Date.self) { date in
                EntryView(date: date)
            }
        }
        .fullScreenCover(isPresented: $quickCapture.isPresented) {
            QuickCaptureSheet()
        }
        .onAppear {
            if settings.justCompletedWizard {
                settings.justCompletedWizard = false
                path.append(DateUtilities.startOfDay(for: .now))

                // The launch-time catch-up already ran before the wizard
                // could grant any permissions, so kick the historical
                // backfill here too — this is the moment a fresh install
                // first has signal sources to mine.
                let container = context.container
                Task {
                    await DigestEngine.backfillHistoryIfNeeded(in: ModelContext(container))
                }
            }
        }
    }
}
