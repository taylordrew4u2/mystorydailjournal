# My Story: Daily Journal

A native iOS journaling app that guarantees every day has a record. Full
product spec lives in the task/build prompt this repository was scaffolded
from; this README covers what's implemented, how to build it, and what's
next.

## What's here: M1 — Core loop

This is the first of ten milestones described in the build spec, built in
the order the spec itself prescribes: the notification quick-reply
(`UNTextInputNotificationAction`) is the single most important interaction
in the product, so it was built first, before signals, before the digest,
before anything else.

Implemented:

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
- **Zero emoji** — audited; the codebase and every string in it uses SF
  Symbols and plain text only.

Not yet built (see Roadmap below): background signal providers (Health,
Calendar, Photos, Location), digest generation, CloudKit sync, Live
Activity/widgets/Share Extension, Shortcuts ingestion, Screen Time panel,
and the alternate app icons. None of these are missing by oversight — the
build spec explicitly sequences them into M2 through M10, and this
milestone was scoped to ship the core loop on its own first.

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
`com.mystorydailyjournal.app` in `project.yml` is a placeholder.

Run the `MyStoryDailyJournalTests` scheme for unit tests covering the
day-record repository (idempotent lookup, quick-reply append/dedupe) and
guided-entry composition.

### Trying the quick-reply feature

1. Run the app once and complete (or skip) the setup wizard — this is what
   requests notification authorization and schedules the daily reminder.
2. In Settings, set the reminder time a minute or two in the future.
3. Lock the device (or background the app) and wait for the banner.
4. Long-press (or swipe left on) the notification to reveal the "Write"
   text field, type a line, and tap "Save." No app launch, no unlock
   required to type. Reopen the app to see the entry saved to today.

## Architecture notes

- `Signals/DaySignalProvider.swift` defines the protocol every future
  background signal (Health, Calendar, Photos, Location, ...) will
  implement — one provider per `DaySignalKind`, each independently
  disableable, so a denied permission degrades exactly one signal instead
  of breaking digest assembly. No concrete providers ship yet (M3).
- `Persistence/DayRecordRepository.swift` is the single idempotent
  find-or-create path for a day's record — both the background notification
  delegate and the foreground entry views go through it, so "the same day
  looked up twice" never produces a duplicate `DayRecord`.
- `Settings/SettingsStore.swift` holds local, device-specific preferences
  in `UserDefaults` (reminder time, palette, lock settings, wizard state) —
  deliberately separate from the CloudKit-synced `DayRecord` store per the
  build spec's data-model split.

## Roadmap (per the build spec's milestones)

- **M2** — Lock Screen widget, tag-only entries, Siri/Action Button intent,
  voice capture.
- **M3** — Signal providers: HealthKit, Calendar, Photos, Core Location
  visits, one per PR, each with its own wizard step.
- **M4** — Rule-based digest composer, midnight background job with
  foreground catch-up, auto-day UI, convert-to-entry flow.
- **M5** — Full-accuracy location flow, person tagging, attendee
  suggestions.
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
