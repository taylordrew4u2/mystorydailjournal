import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.modelContext) private var context
    @StateObject private var watchedFolder = WatchedFolderManager.shared
    @StateObject private var nearbyPeople = NearbyPeopleService.shared

    private struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    @State private var isChoosingFolder = false

    var body: some View {
        Form {
            Section("Writing") {
                Picker("Default style", selection: $settings.writingStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section("Reminder") {
                DatePicker(
                    "Time",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                Stepper(
                    "Follow-up after \(settings.followUpIntervalMinutes) min",
                    value: $settings.followUpIntervalMinutes,
                    in: 15...240,
                    step: 15
                )
            }

            Section("Signals") {
                Toggle("Steps and workouts", isOn: healthBinding)
                Toggle("Calendar events", isOn: calendarBinding)
                Toggle("Photos", isOn: photosBinding)
                Toggle("Places visited", isOn: locationBinding)
                if settings.locationEnabled {
                    Toggle("Precise location", isOn: fullAccuracyBinding)
                }
            }
            if settings.locationEnabled && settings.fullAccuracyLocationEnabled {
                Section {
                    Text("When precise location is on, opening today's entry takes one exact fix — never a continuous track.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Picker("Palette", selection: $settings.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section("Experimental") {
                Toggle("Rewrite digests in a natural voice", isOn: $settings.digestRewriteEnabled)
                Text("Uses the on-device language model, when available, to smooth out the rule-based digest. Off by default; the plain version is always the fallback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Suggest nearby people", isOn: nearbyPeopleBinding)
                if settings.nearbyPeopleEnabled {
                    TextField("Your name", text: nameBinding)
                        .textFieldStyle(.roundedBorder)
                }
                Text("When on, this phone and a friend's can trade a local handshake to suggest tagging each other — only when they're also running My Story nearby.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("App lock", isOn: $settings.appLockEnabled)
                if settings.appLockEnabled {
                    Picker("Method", selection: $settings.appLockMethod) {
                        Text("Face ID / Touch ID").tag(AppLockMethod.biometric)
                        Text("Passcode").tag(AppLockMethod.customCode)
                        Text("Both").tag(AppLockMethod.both)
                    }
                }
                NavigationLink("Your Data") {
                    YourDataView()
                }
            }

            Section("Watched Folder") {
                if let folderName = watchedFolder.folderDisplayName {
                    LabeledContent("Watching", value: folderName)
                    Button("Stop Watching", role: .destructive) {
                        watchedFolder.stopWatching()
                    }
                } else {
                    Text("Grant one folder — iCloud Drive, a project folder, wherever you keep files — and new files there show up in your daily digest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Choose Folder") {
                        isChoosingFolder = true
                    }
                }
            }

            Section("Your Data") {
                ForEach(DataExporter.Format.allCases) { format in
                    Button("Export as \(format.rawValue)") {
                        do {
                            exportFile = ExportFile(url: try DataExporter.export(format: format, from: context))
                        } catch {
                            exportError = "Couldn't export your journal. Try again."
                        }
                    }
                }
                Button("Delete All Data", role: .destructive) {
                    isConfirmingDelete = true
                }
            }

            Section {
                Button("Redo setup") {
                    settings.wizardCompleted = false
                }
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                watchedFolder.grantAccess(to: url)
            }
        }
        .sheet(item: $exportFile) { file in
            ShareLink(item: file.url) {
                Label("Share export", systemImage: "square.and.arrow.up")
            }
            .padding()
            .presentationDetents([.medium])
        }
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { _ in exportError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Delete everything?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All Data", role: .destructive) {
                do {
                    try DataExporter.deleteAllData(in: context)
                } catch {
                    deleteError = "Some data couldn't be deleted. Try again."
                }
            }
        } message: {
            Text("This deletes every entry on this device and, once it syncs, from your private iCloud database. This can't be undone.")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { _ in deleteError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.reminderMinutesSinceMidnight / 60
                components.minute = settings.reminderMinutesSinceMidnight % 60
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.reminderMinutesSinceMidnight = (components.hour ?? 21) * 60 + (components.minute ?? 0)
                NotificationManager.scheduleDailyReminder(settings: settings)
            }
        )
    }

    /// Turning a signal on here requests OS authorization if it hasn't
    /// been granted yet; turning it off just stops this app from using it
    /// — the OS grant itself is only revocable from system Settings (§12).
    private var healthBinding: Binding<Bool> {
        Binding(
            get: { settings.healthEnabled },
            set: { newValue in
                if newValue {
                    Task { settings.healthEnabled = await HealthSignalProvider().requestAuthorization() }
                } else {
                    settings.healthEnabled = false
                }
            }
        )
    }

    private var calendarBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { newValue in
                if newValue {
                    Task { settings.calendarEnabled = await CalendarSignalProvider().requestAuthorization() }
                } else {
                    settings.calendarEnabled = false
                }
            }
        )
    }

    private var photosBinding: Binding<Bool> {
        Binding(
            get: { settings.photosEnabled },
            set: { newValue in
                if newValue {
                    Task { settings.photosEnabled = await PhotosSignalProvider().requestAuthorization() }
                } else {
                    settings.photosEnabled = false
                }
            }
        )
    }

    private var locationBinding: Binding<Bool> {
        Binding(
            get: { settings.locationEnabled },
            set: { newValue in
                if newValue {
                    LocationVisitMonitor.shared.requestAlwaysAuthorization()
                    settings.locationEnabled = true
                } else {
                    LocationVisitMonitor.shared.stopMonitoringVisits()
                    settings.locationEnabled = false
                    settings.fullAccuracyLocationEnabled = false
                }
            }
        )
    }

    /// The second, explicit ask on top of `locationEnabled` (§3, §12).
    private var fullAccuracyBinding: Binding<Bool> {
        Binding(
            get: { settings.fullAccuracyLocationEnabled },
            set: { newValue in
                settings.fullAccuracyLocationEnabled = newValue
                if newValue {
                    LocationVisitMonitor.shared.requestTemporaryFullAccuracy(
                        purposeKey: LocationVisitMonitor.fullAccuracyPurposeKey
                    )
                }
            }
        )
    }

    /// §13 M10, off by default: starts/stops the local handshake the
    /// instant the toggle changes, using whatever name is already saved.
    private var nearbyPeopleBinding: Binding<Bool> {
        Binding(
            get: { settings.nearbyPeopleEnabled },
            set: { newValue in
                settings.nearbyPeopleEnabled = newValue
                if newValue, !settings.myDisplayName.isEmpty {
                    nearbyPeople.start(displayName: settings.myDisplayName)
                } else {
                    nearbyPeople.stop()
                }
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { settings.myDisplayName },
            set: { newValue in
                settings.myDisplayName = newValue
                if settings.nearbyPeopleEnabled, !newValue.isEmpty {
                    nearbyPeople.start(displayName: newValue)
                }
            }
        )
    }
}

/// Required, plainly-worded in-app content, not a link to a PDF (§12).
struct YourDataView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                Everything you write stays on your device and, if you turn on \
                iCloud, in your own private iCloud account. Nothing is sent \
                to the developer or any other company.

                There is no analytics software in this app and no advertising \
                software. Nothing about your use of the app is tracked.

                If you install the optional Notes or Messages automations, \
                those run entirely inside your own Shortcuts app. Turning an \
                automation off or deleting it in Shortcuts stops it \
                immediately — nothing keeps running on this app's side.
                """)
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Your Data")
    }
}
