# My Story: Daily Journal

A native iOS journaling app that guarantees every day has a record. Full
product spec lives in the task/build prompt this repository was scaffolded
from; this README covers what's implemented, how to build it, and what's
left.

**Built without a Mac or Xcode.** Every line here was written and
reviewed by hand — file structure, API shapes, entitlements — without a
compiler to check it against. That's fine for most of this codebase, but
a handful of newer or sparsely documented frameworks (see "What's left"
below) need real verification on a Mac before they can be trusted as-is.

## What's here: the full build spec, M1 – M10

Built in the order the build spec prescribes: the notification quick-reply
(`UNTextInputNotificationAction`) is the single most important interaction
in the product, so it was built first, before signals, before the digest,
before anything else. M2 (fast capture), M3 (signal providers), M4 (digest
generation), M5 (precise location + people), M6 (CloudKit sync), M7 (Live
Activity, Control Center, Share Extension), M8 (automated ingestion), M9
(lock/trust confirmation, alternate icons, privacy), and M10 (Screen Time,
on-device digest rewrite, nearby people) followed directly on top — every
milestone the build spec describes, including the one it labels deferred.

### M1 — Core loop

- **SwiftData models** — `DayRecord`, `DaySignal`, `Person`, `Tag`, written
  with CloudKit's schema constraints in mind (optional/defaulted fields)
  even though sync itself is a later milestone (M6).
- **Notification quick-reply** — a Time Sensitive daily reminder with a
  `UNTextInputNotificationAction` that saves an entry straight from the
  Lock Screen banner, with no app launch, plus a one-shot follow-up
  escalation if the primary reminder goes unanswered.
- **Freeform + guided full entry** — always switchable per entry regardless
  of the wizard's default; a guided entry always shows its composed text
  for review before saving, never silently.
- **Day list / month grid** — Notes-style reverse-chronological list and a
  Calendar-style month grid behind one segmented control, not two tabs.
- **Setup wizard** — welcome, writing style, reminder time, palette, and an
  optional app-lock offer; skippable at every step, re-accessible from
  Settings ("Redo setup"), and the app is fully usable on its defaults if
  the whole thing is skipped.
- **Optional app lock** — Face ID/Touch ID via `LocalAuthentication` and/or
  a custom code in the Keychain, off by default, offered once.
- **Curated accent-color palette** — eight presets, applied via `.tint()`;
  no free color picker, since each preset needs its own home-screen icon
  variant (M9).
- **"Your Data" screen** — plain-language, in-app statement that nothing
  leaves the device except the user's own iCloud account.

### M2 — Fast capture

- **Tag-only entries** — a row of one-tap chips (Good/Rough/Busy/Quiet/
  Notable) on the entry screen that alone constitute a valid entry; shared
  `TagLogger` is the single write path used by the in-app row, the widget,
  and (later) any other capture surface.
- **Lock Screen widgets** — a new `MyStoryWidgetsExtension` target with two
  widgets: `QuickTagWidget` (accessory circular/rectangular, an interactive
  button that logs a configurable preset tag with **no app launch**, the
  same "phone locked" guarantee as the notification quick-reply) and
  `QuickWriteWidget` (accessory + Home Screen small, taps through to the
  bare-text-field capture sheet via a `mystory://quick-capture` deep link).
- **Quick-capture sheet** — the "opens a bare text field" fast surface:
  nothing on screen but a text field, a mic button, and Save/Cancel.
  Reachable from a toolbar button, the widget, or the Action Button/Siri
  intent when it has no dictated text to attach directly.
- **Voice capture** — on-device `SFSpeechRecognizer`
  (`requiresOnDeviceRecognition = true`) wired into the quick-capture
  sheet's mic button; nothing spoken leaves the device.
- **Siri / Action Button** — `LogTodayIntent` ("Log My Day") exposed via
  `AppShortcutsProvider`; when invoked with no text already supplied, the
  system prompts for it itself (voice-first on Siri), so this can be fully
  hands-free.
- **App Group sharing** — `PersistenceController` now points at the
  app-group container so the host app and the widget extension read and
  write the same SwiftData store.

### M3 — Signal providers

- **`HealthSignalProvider`** — steps, walking/running distance, workout
  summaries via `HKStatisticsQuery`/`HKSampleQuery`.
- **`CalendarSignalProvider`** — attended events (declined/canceled
  filtered out) via `EKEventStore`; attendee names ride along for M5's
  suggestion chips but are never written anywhere unconfirmed.
- **`PhotosSignalProvider`** — photo/screenshot counts via `PHAsset`
  fetches; stores local identifiers only, never image bytes.
- **`LocationVisitMonitor` + `LocationSignalProvider`** — place-level
  `CLVisit`s captured live (there's no API to pull visit history on
  demand) and written straight to the day they occurred, with cached
  reverse geocoding. Also owns the one-shot full-accuracy fix M5 builds on.
- **Wizard step 4 ("Signals")** — one signal at a time, each with its own
  plain-language screen before its system prompt fires, individually
  skippable; mirrored by four toggles in Settings so any signal can be
  turned off later without hunting through system Settings.

### M4 — Digest generation

- **`DigestComposer`** — deterministic, offline, rule-based template
  assembly in the spec's priority order (places, calendar, photos,
  activity, weather); no model calls, no network.
- **`DigestEngine`** — finds-or-creates the day's record, regenerates only
  the signals it collects itself (visits are left alone), composes, and
  saves as `.autoGenerated`. Re-running for the same day is a no-op past
  the first successful pass, and never touches a day the user actually
  wrote.
- **`DigestScheduler`** — a `BGAppRefreshTask` around local midnight for
  the best-effort path, plus a foreground catch-up on every launch that
  walks every unchecked day up to yesterday — the reliable path, since
  background execution isn't guaranteed (§3, §14: a week-long gap must
  still backfill fully on next open).
- **Auto-day UI** — an "Auto" badge in the day list, a banner on the entry
  screen that disappears the moment the user starts typing, and a fixed
  "Convert" swipe action that now opens the entry for editing instead of
  silently relabeling it.

### M5 — Precision location + people

- **Full-accuracy location** — a Settings toggle on top of the base
  "Places visited" signal; when on, `LocationVisitMonitor.captureExactLocation`
  requests the temporary full-accuracy grant, takes one on-demand fix when
  today's entry opens (never continuous tracking), and reverse-geocodes to
  a street-level placemark only if that grant actually came through,
  falling back to the same neighborhood-level naming visits use otherwise.
- **One-tap person tagging** — a "With" row of already-tagged people, a
  recent-people row sourced from the last ~60 days, and free-text "add
  someone new," all going through `PeopleRepository` so "the same person"
  is recognized by name across days.
- **Calendar-attendee suggestions** — a dashed-border suggestion row built
  from the attendee names M3's `CalendarSignalProvider` already collects;
  tapping one is what turns it into a real, confirmed `Person` tag — it's
  never written as fact on its own.

### M6 — CloudKit sync

- **`PersistenceController`** now configures its `ModelConfiguration` with
  `cloudKitDatabase: .private("iCloud.com.mystorydailyjournal.app")` — the
  same one line the M1 comment promised, made possible because every model
  was already written CloudKit-safe (optional/defaulted fields, no
  schema-level unique constraints).
  **Version-sensitive** (§18): confirm SwiftData's current CloudKit
  constraint/relationship support, and that one on-disk store safely
  serves both the CloudKit-configured app and the widget extension, before
  shipping this as-is.
- **`CloudAccountStatus`** watches `CKContainer.accountStatus()` and
  **`CloudStatusBanner`** shows a plain-language, non-blocking notice when
  iCloud is signed out or unreachable — the app is fully usable either way
  (§11: sync is additive, never blocking).
- **`DataExporter`** — Markdown and JSON export via `ShareLink`, and a
  destructive "Delete All Data" action. Because the store is CloudKit-
  backed, a local delete syncs as a tombstone to the private database the
  same way any other change does; that sync isn't independently
  confirmable from the app, which the delete confirmation says plainly
  rather than promising more than it can guarantee.

### M7 — Live Activity, Control Center, Share Extension

- **`JournalLiveActivity`** — Lock Screen and Dynamic Island presence
  driven by `JournalActivityAttributes.ContentState`, which literally has
  no field that could carry journal text — "shows the prompt only" (§5)
  isn't a UI convention here, it's structurally impossible to violate.
  `LiveActivityManager` refreshes it from every save path in the app
  (quick reply, freeform, guided, quick capture) and on each foreground;
  restarted opportunistically rather than on a guaranteed midnight timer,
  since background execution isn't guaranteed (§3).
- **`LogEntryControl`** — a Control Center control that opens the app to
  quick capture. Its `AppIntent` writes to a new shared
  `PendingActionStore` instead of relying on App Intents' app-opening
  deep-link mechanics, which are genuinely uncertain enough to flag for
  verification (§18) — a plain flag plus the scenePhase handling that
  already runs on every foreground is certain to work.
  **Version-sensitive** (§18): confirm `ControlWidget`'s current API and
  its availability inside the same widget extension bundle.
- **Share Extension** (`MyStoryShareExtension`, a new target) — the
  dependable push path from any app (§3): pulls shared text/URL from
  `NSExtensionContext`, shows it in a SwiftUI compose screen, and saves
  through the new shared `SharedItemIngestor`. Ingested content becomes a
  `sharedItem` `DaySignal` on today's record rather than overwriting
  `bodyText` — the same shape M8's Shortcuts pipeline will use, so both
  paths mean the same thing once they land in the data model.

### M8 — Automated ingestion

- **`IngestSharedContentIntent`** — the one endpoint both Shortcuts
  pipelines hand off to, sharing `SharedItemIngestor` with the Share
  Extension so a note pulled automatically and one forwarded by hand land
  identically. `openAppWhenRun = false`, so a Shortcut using it completes
  with no app switch.
- **`ShortcutTemplate` + the wizard's Automations step** — offered, but
  deliberately secondary, per §7. Honest about a real constraint: a
  `.shortcut` file is a signed binary plist built inside the Shortcuts app
  itself, not something this codebase can author as source. Until a real
  exported one is hosted and wired in, the "Install automation" buttons
  open the Shortcuts app directly and the UI spells out the handful of
  actions to add by hand — a working, if less polished, path rather than
  a placeholder that does nothing.
- **`WatchedFolderManager`** — the Files substitute from §3: one
  `.fileImporter`-granted folder, a security-scoped bookmark, and a
  content diff on every foreground/midnight check that records new file
  names as `fileWatch` signals — which now also show up in the digest
  text, per §14's acceptance criteria.
- Fixed a real bug caught while wiring this up: `DigestEngine`'s
  regeneration was deleting every non-visit signal on each run, which
  would have silently wiped out shared items and watched-folder files
  pushed in by these independent paths. It now only clears signals it
  collects itself.

### M9 — Lock/trust confirmation, alternate icons, App Privacy

- **App lock and "Your Data"** were already built end to end back in M1
  (§7's own step sequencing puts them there) — this pass re-reviewed both
  rather than rebuilding them, and found nothing to change.
- **Alternate app icons** — a real, if intentionally provisional,
  `Design/AppIcon-Master.svg` (closed book, visible spine, one shading
  tone, no gradients, no text — §17's own description) rendered into all
  eight palette presets via `scripts/generate_app_icons.py`
  (`AppIcon.appiconset` for ink, `AppIcon-<theme>.appiconset` for the
  rest), wired through `CFBundleIcons`/`CFBundleAlternateIcons` in
  Info.plist. `SettingsStore.theme`'s `didSet` now calls
  `UIApplication.setAlternateIconName` — switching the palette updates the
  tint and the home screen icon together, per §17's acceptance criterion.
  Honest caveat: this is a functional icon set, not final production
  art — a hand-finished pass per preset is still real design work someone
  should do before shipping.
- **`PRIVACY.md`** — the App Store Connect App Privacy questionnaire
  answer key: every data type this app touches, and why "Data Not
  Collected" is the accurate (not just favorable) declaration for each,
  per §12's own reasoning.

### M10 — Screen Time, on-device digest rewrite, nearby people (deferred)

The build spec itself labels this milestone deferred — built last, and
each piece more speculative than the last:

- **`MyStoryScreenTime`** (a new `DeviceActivityReport` extension target)
  + `ScreenTimePanel`, embedded in today's entry only. This is the
  permanent architecture, not a stand-in for a future export API: the
  report extension's sandbox is deliberately read-only by Apple's own
  design, so no number from it can reach `bodyText` or any stored
  `DaySignal` — structurally, not just by convention.
  **Version-sensitive** (§18): `DeviceActivityReportScene`'s exact shape
  and `DeviceActivityFilter`'s initializer are sparsely documented and
  have moved across releases — confirm both this and the extension
  against the actual SDK before shipping.
- **`DigestRewriter`** — an optional, off-by-default on-device rewrite of
  the rule-based digest via the Foundation Models framework, wrapped in
  `#if canImport(FoundationModels)` and falling back to the plain
  rule-based text on any failure — unavailable model, thrown error, empty
  response. **Best-effort and version-sensitive** (§18): this framework
  is new enough that its exact API needs confirming, and its hardware/OS
  availability is narrow.
- **`NearbyPeopleService`** — the optional Bluetooth/local-network
  handshake via `MultipeerConnectivity`, off by default. Deliberately
  never establishes an `MCSession`: the browser side's
  `foundPeer(_:withDiscoveryInfo:)` callback alone is enough to surface a
  name suggestion, so the feature never asks for more than the Local
  Network prompt discovery itself requires.

None of M10 is missing by oversight — the build spec explicitly sequences
it last and calls it out as deferred, which this follows literally: it's
the final milestone, built after everything else was solid.

## Building

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the
`.xcodeproj` isn't checked in — it's generated from `project.yml`, which
avoids Xcode-project merge conflicts.

```sh
brew install xcodegen
xcodegen generate
open MyStoryDailyJournal.xcodeproj
```

Requires Xcode 16+, iOS 18 SDK. Set your own development team and bundle
identifier prefix in Xcode's signing settings before running on a device —
`com.mystorydailyjournal.app` (and `.widgets` for the extension) in
`project.yml` are placeholders. The App Group identifier
(`group.com.mystorydailyjournal.app`, in both targets' entitlements) needs
to exist under your own team in the Apple Developer portal for the app and
widget to actually share data on device; `PersistenceController` falls back
to a local-only store if the group container can't be resolved, so the app
still runs without it, just without widget/app data sharing.

Run the `MyStoryDailyJournalTests` scheme for unit tests covering the
day-record repository (idempotent lookup, quick-reply append/dedupe),
guided-entry composition, and tag logging.

### Trying the quick-reply feature

1. Run the app once and complete (or skip) the setup wizard — this is what
   requests notification authorization and schedules the daily reminder.
2. In Settings, set the reminder time a minute or two in the future.
3. Lock the device (or background the app) and wait for the banner.
4. Long-press (or swipe left on) the notification to reveal the "Write"
   text field, type a line, and tap "Save." No app launch, no unlock
   required to type. Reopen the app to see the entry saved to today.

### Trying the Lock Screen widgets

1. Build and run once so the widget extension is embedded and discoverable.
2. On the Lock Screen, long-press to edit, add a widget, and pick either
   "Quick Tag" (choose which preset tag it logs) or "Write Today."
3. Tapping the Quick Tag widget logs that tag to today's entry with the
   phone still locked — no app launch. Tapping Write Today opens the app
   straight into the bare-text-field capture sheet.

## Architecture notes

- `Sources/MyStoryDailyJournalShared/` holds every type that both the app
  and the widget extension need to compile — models, `PersistenceController`,
  `DayRecordRepository`, `TagLogger`, `DaySignalProvider`, date/deep-link
  helpers. It isn't a framework; both targets simply list this folder in
  their `sources:` in `project.yml`, so each compiles its own copy. Anything
  app-only (views, notifications, the wizard) or widget-only (the widget
  views/intents) stays in its own target's folder.
- `MyStoryDailyJournalShared/Signals/DaySignalProvider.swift` defines the
  protocol every signal provider implements — one per `DaySignalKind`, each
  independently disableable. Concrete providers
  (`Sources/MyStoryDailyJournal/Signals/`) are app-only, since none of them
  are needed by the widget extension.
- `Persistence/DayRecordRepository.swift` is the single idempotent
  find-or-create path for a day's record — the background notification
  delegate, the foreground entry views, and the widget/Siri intents all go
  through it, so "the same day looked up twice" never produces a duplicate
  `DayRecord`.
- `Persistence/TagLogger.swift` is the same idea for one-tap tags: the
  in-app chip row and the Lock Screen widget's `LogTagIntent` both call it,
  so there's one place that decides what "tagging a day" means.
- `Support/AppGroup.swift` resolves the shared container URL that
  `PersistenceController` builds its `ModelContainer` against, so the app
  and the widget extension read and write the same on-disk store.
- `Settings/SettingsStore.swift` holds local, device-specific preferences
  in `UserDefaults` (reminder time, palette, lock settings, wizard state) —
  deliberately separate from the CloudKit-synced `DayRecord` store per the
  build spec's data-model split.

## What's left

Every milestone in the build spec (M1 through M10) has a first pass in
this repository. What's left is what no amount of code alone can finish:

- **Design polish** — the app icon set is a functional placeholder (§17
  says as much explicitly); a hand-finished pass per palette preset is
  real design work for a person to do.
- **Version verification** (§18) — several features here were built
  against APIs that are new, sparsely documented, or have moved across
  iOS releases: SwiftData's CloudKit integration, `ControlWidget`,
  `DeviceActivityReport`/`DeviceActivityFilter`, the Foundation Models
  framework, and `Find Notes`/`Open Note`'s per-release Shortcuts
  reliability. Each is flagged in its own file's doc comment; all of them
  need confirming against the actual SDK before this ships.
- **Real `.shortcut` files** — M8's automation templates currently open
  the Shortcuts app with manual setup steps spelled out, since a
  `.shortcut` is a signed binary built inside the Shortcuts app itself,
  not something authorable as source in this repository.
- **App Store Connect setup** — provisioning the App Group, iCloud
  container, HealthKit/WeatherKit/Family Controls entitlements, and
  Sign in with Apple-free account flow under a real team, plus the actual
  App Privacy questionnaire submission `PRIVACY.md` documents.
- **On-device testing** — everything here was written and reviewed
  without access to Xcode or an Apple toolchain; see the note at the top
  of this README.
