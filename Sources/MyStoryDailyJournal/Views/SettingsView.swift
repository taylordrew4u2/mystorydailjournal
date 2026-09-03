import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var cloudStatus: CloudAccountStatus
    @Environment(\.modelContext) private var context
    @StateObject private var watchedFolder = WatchedFolderManager.shared

    private struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    @State private var isChoosingFolder = false
    @State private var pendingDisclosure: DataSourceDisclosure?

    var body: some View {
        Form {
            Section("Writing") {
                Picker("Default style", selection: $settings.writingStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Picker("Tone", selection: $settings.writingTone) {
                    ForEach(WritingTone.allCases) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
                Text("The voice used when entries are written or rewritten for you. The app's job is to remember the day for you, keep asking useful questions when it needs more, and write in a voice that sounds like yours. Learning stays private and syncs through your iCloud when available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                Toggle("Music", isOn: mediaBinding)
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

            Section("Sync") {
                Label(
                    cloudStatus.isAvailable ? "Syncing with private iCloud" : "Saving on this device",
                    systemImage: cloudStatus.isAvailable ? "icloud" : "icloud.slash"
                )
                Text(cloudStatus.isAvailable
                     ? "Entries, notes, tags, places, and what the diary learns sync across your devices through your private iCloud account."
                     : "Everything still saves here. Cross-device sync resumes when this device can use your private iCloud account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Generated Diary") {
                Toggle("Write generated diary entries", isOn: $settings.generatedDiaryEnabled)
                Text(settings.generatedDiaryEnabled
                     ? "When you forget to write, the app can turn collected facts into a plain diary draft."
                     : "When you forget to write, the app shows the collected facts instead of writing a diary draft.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Rewrite digests in a natural voice", isOn: $settings.digestRewriteEnabled)
                    .disabled(!settings.generatedDiaryEnabled)
                Text("Uses the on-device language model, when available, to smooth out the rule-based digest. Off by default; the plain version is always the fallback.")
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
                NavigationLink("What this app knows about you") {
                    ProfileReviewView()
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

            Section("Data") {
                NavigationLink("How your data is used") {
                    YourDataView()
                }

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
        .sheet(item: $pendingDisclosure) { disclosure in
            DataSourceAgreementView(
                disclosure: disclosure,
                onAgree: {
                    pendingDisclosure = nil
                    enable(disclosure.source)
                },
                onCancel: { pendingDisclosure = nil }
            )
        }
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

    /// Turning a signal on first shows its plain-language disclosure —
    /// exactly what's read, kept, and what ever leaves the phone — and only
    /// an explicit "I Agree" fires the OS authorization prompt (§12).
    /// Turning it off just stops this app from using it — the OS grant
    /// itself is only revocable from system Settings.
    private func disclosureGatedBinding(
        isOn: @escaping () -> Bool,
        disclosure: DataSourceDisclosure,
        turnOff: @escaping () -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { isOn() },
            set: { newValue in
                if newValue {
                    pendingDisclosure = disclosure
                } else {
                    turnOff()
                }
            }
        )
    }

    private var healthBinding: Binding<Bool> {
        disclosureGatedBinding(isOn: { settings.healthEnabled }, disclosure: .health) {
            settings.healthEnabled = false
        }
    }

    private var calendarBinding: Binding<Bool> {
        disclosureGatedBinding(isOn: { settings.calendarEnabled }, disclosure: .calendar) {
            settings.calendarEnabled = false
        }
    }

    private var photosBinding: Binding<Bool> {
        disclosureGatedBinding(isOn: { settings.photosEnabled }, disclosure: .photos) {
            settings.photosEnabled = false
        }
    }

    private var mediaBinding: Binding<Bool> {
        disclosureGatedBinding(isOn: { settings.mediaEnabled }, disclosure: .media) {
            settings.mediaEnabled = false
        }
    }

    private var locationBinding: Binding<Bool> {
        disclosureGatedBinding(isOn: { settings.locationEnabled }, disclosure: .location) {
            LocationVisitMonitor.shared.stopMonitoringVisits()
            settings.locationEnabled = false
            settings.fullAccuracyLocationEnabled = false
        }
    }

    /// The second, explicit ask on top of `locationEnabled` (§3, §12).
    private var fullAccuracyBinding: Binding<Bool> {
        disclosureGatedBinding(isOn: { settings.fullAccuracyLocationEnabled }, disclosure: .preciseLocation) {
            settings.fullAccuracyLocationEnabled = false
        }
    }

    /// Runs only after the user tapped "I Agree" on the source's disclosure.
    private func enable(_ source: DataSourceDisclosure.Source) {
        switch source {
        case .health:
            Task { settings.healthEnabled = await HealthSignalProvider().requestAuthorization() }
        case .calendar:
            Task { settings.calendarEnabled = await CalendarSignalProvider().requestAuthorization() }
        case .photos:
            Task { settings.photosEnabled = await PhotosSignalProvider().requestAuthorization() }
        case .media:
            Task { settings.mediaEnabled = await MediaSignalProvider().requestAuthorization() }
        case .location:
            LocationVisitMonitor.shared.requestAlwaysAuthorization()
            settings.locationEnabled = true
        case .preciseLocation:
            settings.fullAccuracyLocationEnabled = true
            LocationVisitMonitor.shared.requestTemporaryFullAccuracy(
                purposeKey: LocationVisitMonitor.fullAccuracyPurposeKey
            )
        }
    }

}

/// Plain-language, per-source consent copy (§12): exactly what's read,
/// what's kept, what — if anything — ever leaves the phone, and why the
/// app wants it. Shown before any OS permission prompt fires, in both the
/// onboarding wizard and Settings; nothing turns on without an explicit
/// "I Agree."
struct DataSourceDisclosure: Identifiable {
    enum Source: String {
        case health, calendar, photos, media, location, preciseLocation
    }

    let source: Source
    let title: String
    let reads: String
    let keeps: String
    let leavesPhone: String
    let why: String

    var id: String { source.rawValue }

    static let health = DataSourceDisclosure(
        source: .health,
        title: "Steps and workouts",
        reads: "Step count, distance, workouts, and sleep hours from Apple Health. Read-only — nothing is ever written to Health.",
        keeps: "Daily totals and one-line workout summaries, stored with that day's entry.",
        leavesPhone: "Nothing goes to the developer or anyone else. The saved diary summary can sync to your private iCloud when sync is available.",
        why: "So days you don't write still remember how much you moved and slept."
    )

    static let calendar = DataSourceDisclosure(
        source: .calendar,
        title: "Calendar events",
        reads: "Events on your calendars: title, time, and location. Declined and cancelled events are skipped.",
        keeps: "Event titles, times, and locations, stored with that day's entry. Guest lists are not saved or used as people suggestions.",
        leavesPhone: "Nothing.",
        why: "So an auto-written day can say what actually happened, when, and where."
    )

    static let photos = DataSourceDisclosure(
        source: .photos,
        title: "Photos",
        reads: "Only the details of photos taken each day: how many, when, whether they're screenshots, and where they were taken. Never the pictures themselves.",
        keeps: "Counts, photo identifiers, and one place name per day.",
        leavesPhone: "One photo's location per day may be sent to Apple — and only Apple — to look up a place name and that day's weather. No images ever leave your phone.",
        why: "\u{201C}Took five photos around the park in the afternoon\u{201D} says a lot about a day."
    )

    static let media = DataSourceDisclosure(
        source: .media,
        title: "Music",
        reads: "Recently played songs from your music library.",
        keeps: "Song titles, stored with that day's entry.",
        leavesPhone: "Nothing.",
        why: "So a day can remember what you listened to."
    )

    static let location = DataSourceDisclosure(
        source: .location,
        title: "Places visited",
        reads: "Place-level visits — where you arrived and how long you stayed. Not a continuous track of your movements.",
        keeps: "Place names and visit locations, stored with that day's entry.",
        leavesPhone: "Visit locations are sent to Apple — and only Apple — to look up a place name and that day's weather. Never the developer, never anyone else.",
        why: "So days you don't write still remember where you were."
    )

    static let preciseLocation = DataSourceDisclosure(
        source: .preciseLocation,
        title: "Precise location",
        reads: "One exact location fix at the moment you open today's entry. Nothing runs in the background.",
        keeps: "That single point, attached to today.",
        leavesPhone: "Same as places visited: sent only to Apple for the place name and weather lookups.",
        why: "Street-level accuracy for today's story instead of neighborhood-level."
    )
}

/// The consent sheet itself: the four facts, then an explicit choice.
struct DataSourceAgreementView: View {
    let disclosure: DataSourceDisclosure
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(disclosure.title)
                .font(.title3.weight(.semibold))
                .padding(.top, 24)

            disclosureRow("What it reads", disclosure.reads, systemImage: "eye")
            disclosureRow("What it keeps", disclosure.keeps, systemImage: "internaldrive")
            disclosureRow("What leaves your phone", disclosure.leavesPhone, systemImage: "arrow.up.forward.circle")
            disclosureRow("Why", disclosure.why, systemImage: "questionmark.circle")

            Spacer()

            Button("I Agree — Turn On") { onAgree() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button("Not Now") { onCancel() }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.large, .medium])
    }

    private func disclosureRow(_ label: String, _ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.footnote)
            }
        }
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

                Every data source is optional, off until you agree to it, \
                and can be turned off any time in Settings. What each one \
                shares, in full:

                • Steps and workouts — daily totals and workout summaries \
                from Apple Health. Never leaves your journal.
                • Calendar — event titles, times, and locations. Names can \
                become private relationship prompts; they are not shown as \
                diary tags. Never leaves your journal.
                • Photos — counts, timestamps, and where photos were taken; \
                never the images. One photo's location per day may go to \
                Apple (no one else) for a place name and weather.
                • Music — recently played song titles. Never leaves your \
                journal.
                • Places visited — arrival/departure visits, not a \
                continuous track. Visit locations go to Apple (no one else) \
                for place names and weather.
                • Screen time — shown live on today's entry only; Apple's \
                design makes it impossible for the app to store or export it.
                • AI rewriting — runs entirely on this phone. Your words \
                are never sent anywhere to be rewritten.
                • Personalization — the app's purpose is to remember for you \
                without sounding like a tracker. To do that, it reads your own \
                entries and keeps what it notices: names you mention, the \
                places you name, the rhythms of your week, recurring themes, \
                and how you write. This is worked out on this phone, stored \
                with your journal (so it syncs to your own iCloud and nowhere \
                else), and every single thing it has concluded can be read, \
                muted or deleted under "What this app knows about you" — where \
                learning can also be turned off entirely.
                • Notes, photos, and files you attach — notes verbatim, \
                photo identifiers, and file names only, never file contents.
                """)
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Your Data")
    }
}
