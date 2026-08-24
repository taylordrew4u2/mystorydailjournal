import SwiftUI

/// §16: "Two views, one toggle, not two tabs." A segmented control switches
/// between the List and Month Grid, not separate tab bar items.
struct RootView: View {
    private enum Layout: String, CaseIterable {
        case list = "List"
        case month = "Month"
    }

    @EnvironmentObject private var settings: SettingsStore
    @State private var layout: Layout = .list
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
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
            .navigationTitle("My Story")
            .toolbar {
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
        .onAppear {
            if settings.justCompletedWizard {
                settings.justCompletedWizard = false
                path.append(DateUtilities.startOfDay(for: .now))
            }
        }
    }
}
