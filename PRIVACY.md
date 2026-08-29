# App Store Connect: App Privacy questionnaire

Build spec §12: "for every data type that never leaves the device or the
user's own CloudKit private container ... the accurate declaration is
**Data Not Collected** — the developer has no server and never receives
it." This document is the answer key for App Store Connect's App Privacy
section, current as of iOS 18/2026-era App Store Connect. Re-verify the
exact category list there before submitting — Apple has changed this
questionnaire's categories before.

## Data types this app touches

| Data type | Where it's used | Declaration |
|---|---|---|
| Precise Location | `LocationVisitMonitor`, full-accuracy fix (§3, §5 M5) | **Data Not Collected** |
| Coarse Location | Place-level `CLVisit`s (§4 M3) | **Data Not Collected** |
| Photos or Videos | `PhotosSignalProvider` — asset identifiers and screenshot flag only, never image bytes (§4 M3) | **Data Not Collected** |
| Health | `HealthSignalProvider` — steps, distance, workouts, read-only (§4 M3) | **Data Not Collected** |
| Contacts | `Person` entities — freeform names only, no `CNContact` linking (§12) | **Data Not Collected** |
| Other User Content | `DayRecord.bodyText`, `DaySignal` payloads, calendar event titles/attendees, shared/ingested text (§4, §10) | **Data Not Collected** |
| User ID | None — no account system beyond the user's own Apple ID/iCloud (§15) | **Data Not Collected** |

There is no analytics SDK, no ad SDK, no crash reporter that phones home,
and no third-party network calls other than Apple's own frameworks
(WeatherKit, CloudKit, and the Maps lookups behind reverse geocoding and
the "where was this?" place options) acting on the user's behalf. `NSUserTrackingUsageDescription`
is deliberately absent from Info.plist (§15) — this app doesn't track
across other apps or websites, so App Tracking Transparency doesn't apply,
and adding the key without real tracking behind it is itself a red flag in
review.

## Why "Data Not Collected" is accurate here, not just favorable

"Data Not Collected" specifically means the data never reaches the
developer or a third party — it does **not** mean the data is never
processed on-device or never leaves the device at all. CloudKit sync is
the one channel that does leave the device, and it's covered by Apple's
own standard exemption: data that syncs only to the user's private
CloudKit database, under their own Apple ID, with no access by the
developer, doesn't count as "collected" by this app. WeatherKit similarly
routes through Apple's own infrastructure on the user's behalf, not to
this app's (non-existent) servers. The same holds for MapKit: naming a
place sends a coordinate to Apple Maps and gets venue names back — no
entry text, no photos, and nothing about who the user is, goes with it.

If a future milestone adds anything that changes this — a server
component, a third-party SDK, an analytics tool — this table needs a
matching update before that build ships, and the relevant category's
declaration needs to change to whatever's actually true then.

## Family Controls / Screen Time (M10)

If the `DeviceActivityReport` panel from M10 ships, it's a **display-only**
embedded view — no screen-time number is ever written into `DaySignal` or
any other stored text (§3, §14: "no screen-time number ever appears in
stored text anywhere in the app"). That panel's content isn't collected
either, for the same reason as the rest of this table: it never reaches
this app's process in a form it could store or transmit, by Apple's own
sandbox design for that extension.
