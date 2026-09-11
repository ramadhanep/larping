# Larping (iOS)

SwiftUI iOS app. Brand "Larping", tagline "actually works". Black/white
monochrome aesthetic (Grok-style space theme) with an adaptive brand accent
(`#463CFF` light mode, `#CEFE06` lime dark mode).

**Fully offline, no server, no account.** All data is stored on-device in
SwiftData (SQLite) — there is zero networking in this app. Think Strava, but
just the recording, and private by construction (nothing ever leaves the
device).

Read `docs/ARCHITECTURE.md` first (current structure), `docs/STATUS.md`
(how it got here / commit log), `docs/KNOWN_ISSUES.md` (known gaps). The docs
are written so a fresh session understands the whole app without re-reading
source.

## Features

- **Record** — GPS tracking (background-capable, elevation gain) with live
  map. **Finish auto-saves**; no save form, no "discard your workout" risk.
  Sport picked before starting. Location button lives in the nav bar
  (top-trailing); the map is full-bleed.
- **Activities** — list auto-refreshes via `@Query`; detail shows route map +
  bold stat tiles + delete (plain right-aligned link).
- **Share** — 1080x1920 (Instagram Story ratio) card: route path line + big
  centered sport icon + "LARPING <SPORT>" header + centered white stats (mini 3
  rows), over a photo (camera/library, full-bleed dimmed) or space-black bg.
  Pace is shown without the ` /km` unit; speed sports keep `km/h`. Shared via
  the system share sheet.
- **GPX import** — `.gpx` file → activity (`source: gpx_import`).
- **Stats** — last-7-days distance chart + per-sport totals.
- **Sample data** — one-time seed (7 activities, all sports, last 7 days,
  organic random-walk paths) on first install so the app isn't empty. Users
  can delete everything; it never re-seeds (`seedSampleDataV1` flag).
- **Backup** — Profile → Export all as JSON to Files/**iCloud Drive**, and
  Import backup back (idempotent — existing ids are skipped).
- **Appearance** — light/dark/system toggle, persisted.

## Data

Everything lives in the SwiftData store: `CDActivity` + `CDTrackPoint`
(cascade delete). No network, no auth, no tokens. Cosmetics (display name,
bio, appearance) are `@AppStorage`.

Data lives only on this device. To keep it safe / move devices: **Profile →
Export all activities** (save the JSON in iCloud Drive / Files), then
**Profile → Import backup**. No scheduled/automatic backup yet
(`docs/KNOWN_ISSUES.md`).

## Build & verify

```bash
xcodebuild -project larping.xcodeproj -scheme larping \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build \
  2>&1 | grep -Ei "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

Known non-code warnings that always appear (don't chase them): the
`AccentColor` asset-symbol redeclaration warning, and the
`appintentsmetadataprocessor` "no AppIntents.framework" note.

## Known limits (summary)

- Route map in detail uses Apple Maps → needs network for tiles; the recorded
  **data** is always offline.
- True background iCloud sync would need an iCloud/CloudKit entitlement
  (paid Apple Developer Program) — today it's manual export to iCloud Drive.
- Live-record notification (Dynamic Island/Lock Screen) is NOT built — needs
  a Widget Extension target, see `docs/KNOWN_ISSUES.md`.

## Contributing

See `CONTRIBUTING.md` for setup, conventions, and PR process.