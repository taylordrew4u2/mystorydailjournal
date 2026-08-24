# My Story: Daily Journal

A native iOS journaling app that guarantees every day has a record. Full
product spec lives in the task/build prompt this repository was scaffolded
from; this README covers what's implemented, how to build it, and what's
next.

## What's here: M1 – M5

Built in the order the build spec prescribes: the notification quick-reply
(`UNTextInputNotificationAction`) is the single most important interaction
in the product, so it was built first, before signals, before the digest,
before anything else. M2 (fast capture), M3 (signal providers), M4 (digest
generation), and M5 (precise location + people) followed directly on top.

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
  no free color picker, since each preset will eventually need its own
  hand-finished home-screen icon (M9).
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

Not yet built (see Roadmap below): CloudKit sync, Live Activity, Share
Extension, Shortcuts ingestion, Screen Time panel, and the alternate app
icons. None of these are missing by oversight — the build spec explicitly
sequences them into M6 through M10.

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

## Roadmap (per the build spec's milestones)

- **M6** — CloudKit sync via SwiftData, account-status handling,
  offline-first verification.
- **M7** — Live Activity, Control Center control, Share Extension.
- **M8** — Shared ingestion `AppIntent`, Notes/Message Shortcuts templates,
  watched-folder grant flow.
- **M9** — App-lock end-to-end confirmation, "Your Data" screen (both
  already present in M1), alternate app icons, App Privacy questionnaire.
- **M10** — Family Controls entitlement + `DeviceActivityReport`,
  optional on-device digest rewrite, optional nearby-people Bluetooth
  handshake.
