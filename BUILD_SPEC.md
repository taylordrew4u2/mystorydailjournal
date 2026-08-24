# Build Prompt — My Story: Daily Journal

This is the original build prompt this repository was scaffolded from,
kept verbatim so the spec travels with the code instead of living only in
a chat transcript. `README.md` tracks what's actually been built against
it, section by section.

---

## 0. Read first

Every constraint below has a real solution — this section is a checklist of what's actually solved, not a list of dead ends. Two things stay genuinely impossible no matter the engineering effort (silent reading of Notes/Messages content, and pulling a Screen Time number out of its report extension); everywhere else — including those two features' actual underlying goal — there's a shipped answer. Do not design around the original assumptions; design to what's below.

**Notes — solved as a two-path pipeline.** Direct reading is impossible, permanently: no public API exists, and the sandbox reason for that isn't going away. The real solution has two legs: a Share Extension for one-tap manual push, and a pre-built Shortcuts automation the app offers on first run — a Time-of-Day trigger running `Find Notes` (created today, optionally scoped to a folder like "Journal") that hands results straight to the app's own ingestion `AppIntent`, no user action needed after setup. `Find Notes` has had real reliability bugs across specific iOS releases, so the Share Extension ships as the dependable path, not an afterthought. Full architecture in §3.

**Messages — solved the same way, and it's actually the stronger case.** Same permanent sandboxing as Notes. But Shortcuts' **Message** communication trigger fires on receipt, filters by sender or content, and runs immediately with no confirmation tap — a pre-built automation scoped to senders the user picks (not an unscoped "every message") hands the text straight to the same ingestion `AppIntent`. Plus the Share Extension for one-off forwards. Full architecture in §3.

**People present — solved to the real ceiling, with one narrow bonus.** No iOS API reports nearby people; that was never going to be a background signal. The actual, reliable solution: one-tap manual tagging plus suggested calendar attendees the user confirms. An optional, deferred extra — two installs of this app trading a Bluetooth handshake to auto-suggest each other — covers the narrow case where a friend also uses the app; it's a bonus on top of the real solution, not a replacement for it. Full spec in §3.

**Exact location — solved, it just isn't the default "Always" grant.** Default location on iOS is reduced accuracy (~1–5 km) even with Always authorization. Street-level precision is a second, explicit ask: `requestTemporaryFullAccuracyAuthorization`, checked against `accuracyAuthorization == .fullAccuracy`, paired with an on-demand `requestLocation()` fix at meaningful moments rather than continuous tracking. Full detail in §3.

**Screen Time — the entitlement is solved, extraction is permanently walled off by Apple's own design.** Apple's DTS engineers have confirmed directly, on the record, that the report extension's sandbox is intentionally read-only so this specific data category can never cross into a less-restricted process — that's not a current gap, it's the deliberate architecture, and no App Group trick gets around it. What is solved: the Family Controls entitlement itself is not parental-control-only — Apple's current request explicitly accepts a genuine personal digital-wellbeing use case, with approvals commonly landing in days to a few weeks. So the correct, final design is: request the entitlement honestly, embed `DeviceActivityReport` live in the day view, and never plan for its number to reach stored text. Full detail in §3.

**Files created — solved for a folder the user chooses, permanently unsolvable device-wide.** No third-party app watches the whole device's file activity — that's the sandbox working as intended, not a missing API. The real solution: the user grants one folder once via the document picker, the app keeps a security-scoped bookmark, and watches that folder for new files each day. A file that's created and never leaves another app's own private sandbox stays invisible — nothing closes that gap, and the UI shouldn't imply otherwise. Full spec in §3.

**Persistent notifications — solved, the real answer just isn't "persistent."** There is no Android-style ongoing notification. The actual equivalent stack — Live Activity on Lock Screen and Dynamic Island, Lock Screen and Home Screen widgets, a Control Center control, Time Sensitive interruption level — covers the same job completely. Full detail in §3.

**Cloud sync — solved and in scope, not deferred.** CloudKit via SwiftData's built-in CloudKit support syncs the private database across the user's own devices. No custom server, no third-party account. Full spec in §11.

**Build order directive:** the feature that makes this product work is `UNTextInputNotificationAction` — the user types an entry directly into the notification banner with the phone locked, no app launch. Build that first, before signals, before the digest, before anything else. Everything else in this document is secondary to that interaction.

Full detail on all of the above in §3 and §11.

---

## 1. Product

**My Story: Daily Journal** is a native iOS journaling app that guarantees every day has a record. If the user writes an entry, that entry is the day. If the user writes nothing, the app assembles an automatic "day digest" from on-device signals (location visits, photos taken, health/activity, calendar events, screen-time report) and saves that as the day's record instead. The user can later open any auto-generated day and convert it into a real entry.

Two design pillars, in priority order:

1. **No empty days.** A day is never blank. Silence produces a digest.
2. **Sub-five-second capture.** Entering a journal note must be possible from the Lock Screen without unlocking into the app, without reading anything on screen, and without appearing conspicuous in public.

Everything else is secondary — with one exception that overrides everything else in the document: **no emoji, anywhere, in any part of the app.** Not in tags, not in mood or reflection prompts, not in onboarding, not in notifications, not in the Live Activity, not in the App Store listing copy. Icons and plain text only. This is absolute, not a style default — if a later section's example or wording implies otherwise, this line wins.

---

## 2. Targets

- App name: **My Story: Daily Journal** (23 of 30 characters in the App Store name field — room left for the subtitle to carry the rest of the search keywords).
- Swift 6 / SwiftUI, iOS 18 minimum (drop to iOS 17 only if a required API forces it).
- iPhone only. No iPad, no Mac Catalyst in v1.
- SwiftData with CloudKit sync (or Core Data + `NSPersistentCloudKitContainer` if SwiftData's CloudKit support doesn't cover a needed case). No custom backend, no third-party account — sync rides the user's Apple ID private database. See §11.
- App group shared container so widgets, App Intents, and extensions read/write the same store.

---

## 3. Platform constraints — read before designing anything

These are hard iOS limits. Do not design around assumptions that violate them.

**Apple Notes is not readable directly — solved via a two-path ingestion pipeline.** There is no public API for reading the user's Notes database; this is permanent, not a current-SDK gap. Two legitimate paths in, both shipped:
- *Manual:* a Share Extension so the user can push a specific note into the journal in a couple of taps, any time.
- *Near-automatic:* a pre-built Shortcuts automation the app offers to install on first run — an in-app "Install automation" button opens Shortcuts pre-filled via a `.shortcut` link. It sets a Time-of-Day personal automation trigger to run immediately, runs `Find Notes` filtered to `Created Today` (optionally scoped to a folder the user names, e.g. "Journal"), and hands the result to the app's own ingestion `AppIntent`. Author that intent to do its work without opening a foreground UI, so the automation completes with no app switch visible to the user.
- *Caveat:* `Find Notes` and `Open Note` have had genuine reliability regressions in specific iOS releases (17.4 and 18.2 both had reported bugs). Ship the Share Extension as the dependable path; treat the Shortcuts pipeline as a convenience layer on top of it, never the only path.
Design the feature as *push, or pull-via-a-user-installed-Shortcut* — never a silent read of Notes.

**Screen Time: entitlement is realistically obtainable, extraction is permanently blocked — this is the final architecture, not a v1 stopgap.** `DeviceActivityReport` renders inside a sandboxed extension process, and Apple's own DTS engineers have confirmed directly on the developer forums that this is intentional: the report extension's sandbox is deliberately read-only specifically so this category of sensitive data can't be exported to a less-restricted process, App Group storage included. No architecture — UserDefaults suite, shared file, CFPreferences — gets a raw number out of that extension into the host app. That part is closed, permanently. Separately, and genuinely solvable: the Family Controls entitlement itself is not parental-control-only. Apple's current distribution request explicitly accepts a genuine personal digital-wellbeing use case alongside parental control, with developers commonly reporting approval in days to a few weeks per bundle ID (and separately per extension bundle ID). So the correct, complete design is: request the entitlement framed honestly around this app's own daily-reflection purpose, then embed `DeviceActivityReport` live inside the day-detail screen. It's a real, permanent, display-only panel — not a placeholder waiting on an API that's coming. Never attempt to write its value into `bodyText` or a stored `DaySignal`.

**Messages/iMessage is not readable directly — solved the same way, with a stronger automatic path than Notes.** No public framework exposes the Messages database, thread list, participants, or content; the `Messages` framework only supports building a Messages *app extension* (stickers/iMessage apps), not read access to conversations. This is permanent. Two paths in:
- *Manual:* Share Extension, same as Notes.
- *Near-automatic:* Shortcuts' **Message** communication trigger fires on receipt, filterable by Sender and/or Message Contains, and supports "Run Immediately" (no confirmation tap). Ship a pre-built automation template where the user picks which senders to auto-log — e.g. a partner, a specific group thread — not an unscoped "every message" trigger, which is both noisier than the feature needs and a bigger privacy ask than necessary. The trigger's Shortcut Input (sender plus text) passes straight to the same ingestion `AppIntent` used for Notes.
Do not imply in UI copy that the app is scanning messages — it only ever sees what a user-authored, user-scoped automation explicitly hands it.

**People present is inference or manual as the primary, reliable path — plus one narrow optional automatic add-on.** No API reports who else was in a location, on a call, or nearby, so this was never going to be a general background signal. Primary solution, ships in v1: a `Person` entity the user tags onto a `DayRecord` in one tap from a recent-people list, plus `EKEvent` attendee names surfaced as a suggestion the user accepts or dismisses — never written into the digest unconfirmed. That covers the large majority of real use, with zero technical risk. Optional stretch, deferred to §13 M10: if a friend also has this app installed, `MultipeerConnectivity` can run a local Bluetooth handshake between two nearby instances and auto-suggest "with [name]" for both — opt-in, Bluetooth-range only, and only useful when the other person runs this exact app, so treat it as a narrow bonus, not a general solve. Needs `NSLocalNetworkUsageDescription`, `NSBonjourServices`, and a Bluetooth usage string if built — see §15. Photos' on-device Person/Face grouping has no public API with names attached, so photo-based companion detection stays off the table entirely, with or without this add-on.

**Full location precision needs a second, separate ask.** `CLVisit` under Always authorization gives place-level accuracy suitable for "you were near X," not a street address. To get precise coordinates: request `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)`, check `CLLocationManager().accuracyAuthorization == .fullAccuracy` before relying on precision, and pull a one-shot `requestLocation()` fix at meaningful moments (app foreground, journal write) rather than continuous tracking. Reverse-geocode with `CLGeocoder` to a street-level `CLPlacemark` only when full accuracy is granted; fall back to neighborhood-level naming otherwise. Continuous high-accuracy background tracking is both a battery cost and one of the most commonly rejected App Store review categories — do not build it into v1.

**There is no general file system access — solved for a folder the user chooses, not solvable device-wide.** The app sees its own sandbox; no third-party app can watch device-wide file activity, and that's the security model functioning correctly, not a missing API. The shippable solution: `UIDocumentPickerViewController` lets the user grant access to one folder — their iCloud Drive Documents, a specific project folder, wherever they actually keep files — a single time; persist a security-scoped bookmark (`startAccessingSecurityScopedResource`), and watch that folder for files created since the last check, either via `NSFilePresenter` for live change notification while foregrounded, or a `FileManager` enumeration diffed against the prior day's snapshot during the nightly digest pass. This covers someone's actual working folder. A file created and never exported from inside another app's own private sandbox remains genuinely invisible — no engineering path closes that half, and the UI should not imply otherwise. Photos and screenshots via PhotoKit remain the other legitimate substitute for "files."

**iOS has no sticky/ongoing notification.** Android-style persistent notifications do not exist. The equivalent persistence toolkit is:
- **Live Activity (ActivityKit)** on the Lock Screen and Dynamic Island — the only true always-visible surface. Time-boxed, so it must be restarted daily.
- **Lock Screen and Home Screen widgets** (WidgetKit) with an App Intent button for one-tap capture.
- **Control Center control** (`ControlWidget`) and **Action Button** assignment via App Intent.
- **Time Sensitive** interruption level for reminders that break through Focus modes. Critical Alerts require a separate entitlement and will almost certainly be denied for this use case — do not plan on them.

**Background execution is not guaranteed.** `BGAppRefreshTask` and `BGProcessingTask` are scheduled at the system's discretion. Digest assembly must be idempotent and must also run opportunistically on foreground launch, so a day is never lost because the OS skipped a refresh window.

**Permission cost is real.** Always-on location and full Photos access are the two most-rejected prompts in App Store review and the two most likely to be denied by users. Both need in-context pre-permission screens explaining the journaling payoff before the system prompt fires.

---

## 4. Data sources

Implement each behind a `DaySignalProvider` protocol so a denied permission degrades one signal instead of breaking the digest.

| Signal | Framework | Permission | Notes |
|---|---|---|---|
| Places visited | Core Location — `startMonitoringVisits()` (`CLVisit`) | Always | Low battery cost, place-level only. Reverse-geocode with `CLGeocoder`, rate-limited and cached. Do not poll continuous GPS. |
| Precise location | Core Location — `requestTemporaryFullAccuracyAuthorization` + one-shot `requestLocation()` | Always + full accuracy | Street-level fix on demand at app-open/journal-write. Falls back to place-level if user denies full accuracy. See §3. |
| Distance / travel | Core Location significant-change + HealthKit distance | Always / Health read | Derive "traveled ~12 km" rather than storing a raw track. |
| People present | Manual tag + `EKEvent` attendee names (suggested, not auto-written) | Calendar read (for suggestions) | No system API detects nearby people. See §3. |
| Photos & screenshots | PhotoKit — `PHAsset` fetch filtered by `creationDate` | Photos read (limited access supported) | Store local identifiers only. Never copy image data into the app store. Screenshots are detectable via `PHAssetMediaSubtype.photoScreenshot`. |
| Steps, workouts, sleep | HealthKit | Health read | Cheap, high-signal, low review friction. Good first provider to build. |
| Calendar events | EventKit — `EKEventStore` | Calendar read | Include only events the user actually attended (declined/canceled filtered out). |
| Music / media | MediaPlayer `MPMediaLibrary` recently played | Media library | Coverage is inconsistent across streaming apps. Low priority. |
| Screen time | `DeviceActivityReport` extension | Family Controls entitlement | Live display panel, permanently — not extractable into stored text even with the entitlement granted. See §3. |
| Shared-in content, manual | Share Extension | none | One-tap forward from Notes, Messages, Safari, or any app. Always available, the dependable path. |
| Shared-in content, automated | User-installed Shortcuts automation → app's ingestion `AppIntent` | none (user installs/authorizes the automation itself in Shortcuts) | Notes: daily `Find Notes` pull. Messages: per-sender trigger on receipt. Fully revocable by the user inside Shortcuts. See §3. |
| Watched folder | Security-scoped bookmark + `FileManager` diff | Document picker grant, one folder | Substitute for system-wide file visibility, scoped to a folder the user chooses. See §3. |
| Weather | WeatherKit | none | Free contextual color for the digest. |

---

## 5. Capture surfaces

Ranked by required speed. Build 1–3 before anything else.

1. **Notification quick-reply.** `UNTextInputNotificationAction` on the daily reminder. User types directly in the notification banner and it saves. No app launch. This is the single most important feature in the product.
2. **Lock Screen widget + Live Activity button.** App Intent that opens a bare text field, or logs a one-tap mood/tag with no typing at all.
3. **Voice.** App Intent exposing "Log my day" to Siri and the Action Button, plus an in-app record button using `SFSpeechRecognizer` with on-device transcription forced (`requiresOnDeviceRecognition = true`).
4. **One-tap tokens.** A row of emoji-free tag chips (Good / Rough / Busy / Quiet / Notable) that constitute a valid entry by themselves. A day marked with a single tag counts as journaled.
5. **Full editor.** Freeform or guided, warm rather than a blank stare. Full spec in §6.

Public-use requirement: every capture surface must work without the screen displaying prior entries. No preview of past text on the Lock Screen. Live Activity shows the prompt only, never content.

---

## 6. Full entry experience: freeform and guided

Everything in §5 optimizes for speed. This section is the opposite goal — when the user has chosen to actually sit down and write, the screen should feel unhurried and personal, not like a form.

**Two modes, always switchable, one default set during setup (§7):**
- **Freeform.** A plain text canvas. No character counter, no streak warning, no pressure UI of any kind on this screen — those belong to the reminder logic in §8, never here. Opens on the date and nothing else demanding attention; no placeholder copy like "Start typing…" sitting in the field.
- **Guided.** A short sequence of 3–5 prompts, one at a time, each answered in a compact text field — not a long-form essay box per question. On the last question, show the composed result (answers stitched into a couple of short paragraphs, the same lightweight template-composition approach the digest uses in §9) and let the user lightly edit before saving. Never save a guided entry silently without showing the final text first — that's what keeps it feeling like their own writing rather than a form that vanishes.

**Starter question sets**, picked during setup (§7) or replaced with 3–5 custom questions:
- *Simple recap* — "What's one thing that happened today?" / "How are you feeling, in a few words?" / "Anything else worth remembering?"
- *Gratitude* — "What are you grateful for today?" / "What made you smile?" / "One small win, however small?"

Keep prompts in plain, reflective journaling language — not clinical or assessment-style phrasing. This is a diary, not a screening tool, and it should never read like one.

**No emoji anywhere on this screen** — mood and feeling answers are typed text, never an emoji picker. See §1.

**Data model note:** a guided entry, once composed, is stored exactly like a freeform one — `bodyText` in `DayRecord` (§10), `source: userWritten`. The data model doesn't distinguish how the words got there; the distinction only exists in the writing UI itself.

---

## 7. Setup wizard

A first-run flow that front-loads every preference decision so daily use afterward needs none. Never a gate — every step is skippable, the wizard can be exited at any point, and the app is fully usable afterward with sensible defaults (freeform mode, no signals enabled, no lock, default palette). Re-accessible anytime from Settings ("Redo setup") if preferences change later.

**Steps, in order:**
1. **Welcome.** One line on what the app does. No permission prompts yet.
2. **Writing style.** Freeform, guided, or "ask me each time" — sets the default from §6. If guided (or "ask me each time"): pick a starter set or write 3–5 custom questions.
3. **Reminder time.** Feeds §8. A simple morning/evening/custom quick-pick beats a raw time wheel as the first thing shown.
4. **Signals.** Walk Health, Calendar, Photos, and Location from §4 one at a time, each with its own plain-language pre-permission screen before the system prompt fires (per §3's permission-cost note) — never fire every system prompt back to back with no context. Each is individually skippable.
5. **Automations (optional, clearly secondary).** Offer to install the Notes and Message Shortcuts automations from §3. Not front-and-center — someone who just wants the plain app shouldn't feel like they're missing a step by skipping this.
6. **Palette.** One-tap swatch pick from §16.
7. **App lock (optional).** Offered once here, per §12 — off by default even if skipped or declined.
8. **Done.** Lands on today's entry, empty and ready.

**Build sequencing:** the wizard ships incrementally, not as one monolith. The shell plus steps 1–3 and 6–8 land with the core app (M1); each signal's step in 4 is added as that provider lands (M3); step 5 lands with automated ingestion (M8). Full milestone mapping in §13.

**Storage:** these are local preferences (`UserDefaults`), not part of the CloudKit-synced `DayRecord` store in §11 — consistent with how reminder time and lock settings are already handled. Cross-device preference sync via `NSUbiquitousKeyValueStore` is a reasonable v2 addition, not a v1 requirement.

**No emoji anywhere in the wizard UI** — progress indicators and confirmations are plain text or system iconography, never emoji. See §1.

---

## 8. Reminder and escalation logic

- User sets a preferred reminder time, during setup (§7) or later in Settings. Default 21:00.
- Reminder is Time Sensitive so it survives Focus modes.
- If no entry by the reminder time, escalate at a user-set interval (default: one follow-up 90 minutes later).
- At local midnight, if the day still has no user entry, generate the digest and mark the day `autoGenerated`.
- Never nag after the digest is written. The day is closed; the app goes quiet.
- Streak logic counts both user entries and auto-digests as "covered," but tracks a separate "written" count. Do not shame the user for auto days — the entire premise is that auto days are acceptable.

---

## 9. Digest generation

Rule-based composition, not a language model, in v1. Deterministic, offline, zero cost, no data leaves the device.

Template assembly from available signals, in priority order: places visited → calendar events → photos taken → activity → weather. Example output shape:

> Tuesday, March 4. Started at home, spent about four hours in the Flatiron area, then a stop in Williamsburg in the evening. Three calendar events. Took nine photos. 11,400 steps. Rain most of the afternoon.

Optional v2: an on-device Foundation Models pass to rewrite the digest in a more natural voice. Gate it behind a setting, default off, and keep the rule-based output as the fallback.

Digest assembly must be idempotent — running twice for the same day produces one record, not two.

---

## 10. Data model

```
DayRecord
  date: Date (unique, start-of-day, user's timezone)
  source: enum { userWritten, autoGenerated, converted }
  bodyText: String
  tags: [Tag]
  people: [Person]
  createdAt / editedAt: Date
  signals: [DaySignal]

DaySignal
  kind: enum { visit, photo, calendar, activity, weather, sharedItem, screenTime, fileWatch }
  timestamp: Date
  payload: Codable  // identifiers and derived summaries only

Person
  id: UUID
  name: String
  createdAt: Date
```

`Person` is deliberately lightweight and freeform — see §12 for why it never auto-resolves against the system Contacts database. `sharedItem` covers Notes/Messages content regardless of which path delivered it (manual Share Extension or the Shortcuts pipeline in §3) — storage shape is identical either way, only the trigger differs.

Store references, not copies: `PHAsset` local identifiers, `EKEvent` identifiers, coordinates plus a cached place name. Never duplicate photo bytes or full calendar bodies into the journal store.

Timezone handling: a day is bounded by the user's local midnight at the time the day occurred. Store the timezone identifier on the record so travel days do not produce duplicate or missing days.

---

## 11. Cloud sync

Sync is CloudKit, riding the user's own Apple ID private database. No custom backend, no third-party auth, no server to run.

- **SwiftData:** add `.modelContainer(for:, cloudKitDatabase: .private("iCloud.<bundle-id>"))`. Every `@Model` field must have a default value or be optional — CloudKit's schema requires it. Relationships must be optional. No unique constraints — SwiftData/CloudKit doesn't support them, so de-dupe `DayRecord` by date in application logic instead of a schema constraint.
- **Core Data alternative:** `NSPersistentCloudKitContainer` if you need finer control than SwiftData currently exposes (e.g., custom conflict resolution). More boilerplate, same underlying CloudKit private database.
- **Private database only.** No shared/public CloudKit database in v1 — this is a personal journal, not a shared document. No CloudKit sharing UI.
- **Conflict resolution:** CloudKit's default last-write-wins is acceptable for `DayRecord.bodyText` edits from two devices, since same-day edits from one person are rare and low-stakes. Do not build custom merge logic in v1.
- **Offline-first:** the app must be fully usable with iCloud signed out or unreachable. Sync is additive, never blocking — every write lands in the local store immediately regardless of network state.
- **Assets:** photo/document references sync as identifiers, not binary data — the referenced `PHAsset` isn't duplicated into CloudKit, only its identifier and the app's own derived text.
- **Account required:** CloudKit private database requires the user be signed into iCloud. Detect `CKContainer.accountStatus()` and degrade to local-only with a clear banner if signed out, rather than failing silently.
- **`Person` syncs like everything else** — same private database, same offline-first rule, no special-casing.

---

## 12. Privacy & security

- All processing on-device except CloudKit sync (user's own private database, Apple-encrypted at rest and in transit) and WeatherKit/reverse geocoding.
- Explicit `NSPrivacyAccessedAPITypes` entries and a complete privacy manifest.
- Purpose strings written for a human, not for review: state the journaling benefit in each `Info.plist` usage description, including the temporary full-accuracy location prompt.
- Per-signal toggles in Settings, including a toggle for full-accuracy location separate from the base Always-location toggle. Every signal individually disableable without breaking the app.
- Export to Markdown/JSON and full local delete, which must also purge the CloudKit private database, not just the local store.
- **App lock, fully optional, two methods, either or both:**
  - Face ID / Touch ID via `LocalAuthentication`, `LAPolicy.deviceOwnerAuthenticationWithBiometrics` with automatic fallback to device passcode.
  - A custom in-app numeric code (4 or 6 digit, user's choice) stored in the Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never in SwiftData/CloudKit, never synced. This is the option for someone who wants a diary-style lock independent of their device passcode.
  - Default state is **off**. First-run does not prompt for a lock; it's offered once in onboarding and otherwise lives in Settings. No nagging to enable it later.
  - Lock triggers on app background/foreground (configurable delay: immediately, or after 1/5/15 minutes), not on every screen transition.
- Person tags are freeform, user-entered strings stored in the same private database — no contact-matching or identity resolution against the system Contacts database unless the user explicitly picks a contact via `CNContactPickerViewController`.
- **The Shortcuts-delivered pipelines (Notes pull, Message trigger, §3) live entirely in the user's own Shortcuts app, not this app's code.** Turning either automation off or deleting it stops all ingestion immediately, with nothing left running on this app's side. Say this plainly in the "Your Data" screen below.
- **If the optional nearby people-tagging ships (§13 M10), it's off by default, Bluetooth-range only, and does nothing until the user explicitly turns it on.**
- **Data-sharing statement, required in-app content, not just a legal document:** a plain-language screen in Settings ("Your Data") stating in the app's own voice: everything stays on your device and in your own iCloud account; nothing is sent to the developer or any third party; no analytics SDK, no ad SDK, no tracking. This is user-facing copy the team writes deliberately — not boilerplate, and not just a link to a privacy policy PDF.
- App Store Connect "App Privacy" (nutrition label) questionnaire: for every data type that never leaves the device or the user's own CloudKit private container (location, photos, health, calendar, contacts, person tags), the accurate declaration is **Data Not Collected** — the developer has no server and never receives it. Get this right; it's the actual trust signal a user sees before installing, and it's what "we don't share your data" has to cash out as in the App Store listing.

---

## 13. Milestones

**M1 — Core loop.** SwiftData model, day list, freeform + guided full-entry experience (§6), daily notification with `UNTextInputNotificationAction`, wizard shell covering writing-style choice, reminder time, palette, and lock offer (§7 steps 1–3, 6–8). Ship-quality on its own.

**M2 — Fast capture.** Lock Screen widget with App Intent, tag-only entries, Siri/Action Button intent, voice capture.

**M3 — Signals.** HealthKit first, then Calendar (with attendee suggestions), then Photos, then Core Location visits (place-level). One provider per PR, each independently disableable. Each provider's wizard step (§7 step 4) lands alongside it.

**M4 — Digest.** Rule-based composer, midnight `BGAppRefreshTask` plus foreground catch-up, auto-day UI treatment, convert-to-entry flow.

**M5 — Precision and people.** Full-accuracy location flow (§3), one-tap person tagging, calendar-attendee suggestion chips.

**M6 — Sync.** CloudKit via SwiftData, account-status handling, offline-first verification, sync-aware delete/export. Full spec §11.

**M7 — Persistence surfaces.** Daily Live Activity, Control Center control, Share Extension for pushing content in from Notes, Messages, and elsewhere.

**M8 — Automated ingestion.** The ingestion `AppIntent` endpoint shared by both pipelines in §3; pre-built `.shortcut` templates for the Notes daily-pull and the Message trigger; in-app "Install automation" entry points; the watched-folder grant flow for Files. Wizard's optional automation-install step (§7 step 5) lands here.

**M9 — Lock and trust.** Optional Face ID/passcode lock (§12), "Your Data" screen, palette-driven alternate icon set (§17), App Privacy questionnaire filled out. Wizard's lock-setup step (§7 step 7) confirmed end-to-end here.

**M10 — Deferred.** Family Controls entitlement request and `DeviceActivityReport` extension. Optional on-device model rewrite of the digest. Optional nearby people auto-tag via `MultipeerConnectivity` (§3).

---

## 14. Acceptance criteria

- No emoji appears anywhere in the shipped app — audit every screen, not just tags and prompts.
- A guided entry always shows its composed text for review before saving; nothing saves silently.
- Freeform and guided are switchable on every entry, regardless of what the wizard set as default.
- The setup wizard can be exited at any step and the app remains fully usable on sensible defaults.
- A journal entry can be created from a Lock Screen notification in under five seconds with the phone locked.
- No day in the app's lifetime is ever blank.
- Every permission denial degrades exactly one signal and produces a still-useful digest.
- The app functions fully in airplane mode, including with iCloud signed out.
- Killing the app for a week and reopening it backfills every missed day's digest on launch.
- Nothing on any Lock Screen surface reveals journal content.
- A person tag or attendee suggestion never appears in a digest as fact unless the user confirmed it.
- Editing the same day on two synced devices does not silently drop content on either.
- With app lock off (default), the app opens with zero friction. With it on, biometric or code gates every foreground.
- Every screen's background stays neutral; only the accent color changes across palette presets.
- Switching palette presets updates the in-app tint and the home screen icon together.
- Installing the provided Notes automation ingests that day's notes with no further action; deleting it in Shortcuts stops ingestion immediately.
- Installing the provided Message automation logs a picked sender's message within seconds of receipt, and never logs a sender the user didn't select.
- Granting a watched folder surfaces new files from that folder in the next digest; nothing outside that folder is ever touched.
- The Screen Time panel, when present, is always a live embedded view — no screen-time number ever appears in stored text anywhere in the app.

---

## 15. Info.plist keys & entitlements

**Usage description keys** (each string must state the actual benefit, not boilerplate — App Review rejects generic text):

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationTemporaryUsageDescriptionDictionary` — dictionary entry keyed by the purpose string passed to `requestTemporaryFullAccuracyAuthorization`
- `NSPhotoLibraryUsageDescription` — PhotoKit read, limited-library access supported
- `NSCalendarsFullAccessUsageDescription` (iOS 17+) / `NSCalendarsUsageDescription` (pre-17 fallback)
- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription` — only if the app ever writes to Health; omit if read-only
- `NSSpeechRecognitionUsageDescription` — voice capture
- `NSMicrophoneUsageDescription` — voice capture
- `NSFaceIDUsageDescription` — optional app lock
- `NSAppleMusicUsageDescription` — only if the Media Player signal ships
- `NSUserTrackingUsageDescription` — **do not add.** The app doesn't track across other apps or websites, so App Tracking Transparency doesn't apply. Adding this key with no real tracking behind it is itself a red flag in review.
- `NSLocalNetworkUsageDescription`, `NSBonjourServices`, `NSBluetoothAlwaysUsageDescription` — **only if** the optional nearby people-tagging add-on (§3, §13 M10) ships. Omit entirely if that milestone is skipped.

**Other Info.plist entries:**

- `NSSupportsLiveActivities` = true
- `BGTaskSchedulerPermittedIdentifiers` — array of the app's refresh/processing task identifiers, must match what's registered in code
- `UIBackgroundModes` — `processing`, `fetch` (for the BGTask-driven digest assembly in §9), and `remote-notification` (CloudKit's silent push that triggers timely sync in §11)
- `CFBundleIcons` / `CFBundleAlternateIcons` — one entry per palette-preset icon variant, see §17
- `ITSAppUsesNonExemptEncryption` = false — skip the App Store Connect export-compliance question; the app uses only standard OS-level encryption, nothing proprietary

**Entitlements (.entitlements file):**

- HealthKit (`com.apple.developer.healthkit`, plus `com.apple.developer.healthkit.access` if scoping specific types)
- WeatherKit (`com.apple.developer.weatherkit`)
- App Groups (`com.apple.security.application-groups`) — shared container for widgets, App Intents, Share Extension
- iCloud / CloudKit (`com.apple.developer.icloud-services` = CloudKit, plus `com.apple.developer.icloud-container-identifiers`)
- Push Notifications (`aps-environment`) — CloudKit's own sync-change notifications ride APNs; required alongside the `remote-notification` background mode above, even though the app sends no push of its own
- Time Sensitive notifications (`com.apple.developer.usernotifications.time-sensitive`)
- Family Controls (`com.apple.developer.family-controls`) — M10 only, requires a separate Apple approval request, do not assume it will be granted
- Sign in with Apple — not needed, there is no account system beyond the user's own iCloud

---

## 16. Design system

Aesthetic target: the plainness of Notes, the date-forward structure of Calendar. No cards, no shadows, no heavy chrome, generous whitespace, system semantic colors so Dark Mode works for free.

- **No emoji anywhere, full stop.** Not tags, not prompts, not onboarding, not notifications. This is stated once at full strength in §1 — restated here because it's a design-system rule as much as a product rule, and every screen spec below inherits it even where it isn't repeated again.
- **Two views, one toggle, not two tabs.** A segmented control switches between:
  - *List*, Notes-style: reverse-chronological rows, date + first line of text + a small dot indicating written vs. auto-generated day. Swipe actions for delete and convert-to-entry.
  - *Month grid*, Calendar-style: standard month grid, each date cell tinted with the current accent at low opacity if that day is covered, neutral if not. Tap opens the day.
- **Entry screen:** full freeform/guided spec in §6; visually, a plain text canvas first, a thin metadata strip below it for place, weather, tags, and people — styled like a Calendar event's detail rows, not as separate cards.
- **Typography:** system font (SF Pro) for UI and metadata; optionally a serif system font (New York) for the entry body text itself, to read more like a diary than a form.
- **Color palette, user-selectable:** a `Theme` enum backed by a curated set of presets (roughly 8–10 — e.g. ink, forest, rust, slate, plum, ochre, moss, midnight), not an open color picker. See §17 for why. Selecting a preset sets one accent color applied via `.tint()`/environment to buttons, selected dates, highlights, and the app icon together. Backgrounds stay neutral system colors in every preset — only the accent shifts, which is what keeps the app minimal regardless of which color the user picks.

---

## 17. App icon

- A single vector mark: a closed book, simple silhouette, visible spine line, no page detail, no text. Must stay legible at the smallest rendered size (Settings/notification scale, ~29–60pt) — this rules out fine linework.
- Flat fill, at most one shading tone. No gradients or photographic detail — matches the minimal direction of the UI itself.
- **Platform constraint to design around:** iOS app icons are static image assets — there is no runtime recoloring of the home screen icon. "Whatever color the user picked" cannot be generated on the fly. It has to ship as one pre-rendered icon per palette preset from §16, switched at runtime with `UIApplication.shared.setAlternateIconName(_:)`. This is the actual reason the palette is a curated preset list rather than a free RGB/HSB picker — every preset needs a matching hand-finished icon, not an infinite space of them.
- Deliverable: one 1024×1024 master vector (SVG or PDF) of the book mark, then one rendered/exported icon asset per palette preset, each meeting Apple's icon spec (no transparency, no baked-in corner mask — the system applies it).

---

## 18. Verify before building

The following are version-sensitive. Confirm against current Apple documentation and the installed SDK before committing to an approach:

- Current `DeviceActivityReport` extraction limits and the Family Controls entitlement approval process.
- Live Activity maximum duration and daily-restart requirements.
- Whether on-device Foundation Models APIs are available for your deployment target.
- `ControlWidget` availability and capabilities on your minimum iOS version.
- SwiftData's current CloudKit support surface (constraint support, relationship handling) versus the Core Data + `NSPersistentCloudKitContainer` path, for your exact deployment target.
- Current requirements and review posture around `requestTemporaryFullAccuracyAuthorization` purpose strings.
- Current App Store "App Privacy" questionnaire categories, to make sure the Data Not Collected declarations in §12 still map cleanly onto Apple's current category list.
- `Find Notes` / `Open Note` reliability on your exact target iOS version — has had real per-release regressions historically; confirm current behavior before depending on it as anything but a convenience layer.
- Whether a Shortcuts automation can hand data to your app's `AppIntent` without a visible foreground app switch on your target iOS version, versus needing a URL-scheme fallback that does switch apps.
- Current Family Controls request-form wording, to confirm the personal-digital-wellbeing framing in §3 is still accepted the way it's described here.
- `MultipeerConnectivity` / local-network privacy requirements, if the optional nearby-tag add-on (§13 M10) gets built.
- Exact-string availability of "My Story: Daily Journal" in App Store Connect — web search found near-misses ("My Diary App: Daily Journal," "My Journal: Daily Mood Diary") but not this exact string; confirm directly before finalizing icon and marketing assets.
