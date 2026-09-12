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
  Event name auto-fills as "Larping Run" / "Larping Run 1" / "Larping Run 2"…
  (bumps only when that name already exists) and stays editable, but is
  **required** — clear it and Start disables until you fill it back in.
  Sport picked via a compact picker beside the event field; the sport icon
  bounces while recording, and a matching sport-symbol marker rides the live
  route tip on the map (falls back to the system blue dot before you start).
  Location button lives in the nav bar (top-trailing); the map is full-bleed,
  the bottom control card is fully rounded with side/bottom margins so it
  floats above the map, and is a translucent black overlay in dark mode (form
  content stays legible, map shows through faintly).
- **Activities** — list header is the horizontal wordmark (no title text, no
  separate leading toolbar icon — avoids the "glass" chip iOS puts behind
  bare toolbar images); auto-refreshes via `@Query`. A "This week"
  distance/time/count strip sits above the list, and activities are grouped
  into month sections instead of one flat list; each row shows the event
  title (falls back to the sport label). Detail opens with a hero map (route
  draws itself in sync with a bouncing sport-symbol rider, event
  title + sport icon overlaid bottom-left/bottom-right), bold stat tiles, and
  an overflow (`•••`) menu for Share / **Rename event** / Delete.
- **Share** — three swipeable 1080x1920 (Instagram Story ratio) templates:
  a classic card (sport icon + wordmark up top, a big route path line +
  stats, and the date in the footer — no event title, over a photo or a
  **transparent PNG** you can paste anywhere — previewed on a black backing
  so it stays visible in light mode, exported/shared fully transparent), a
  map template (real map fills the background with the wordmark top-right
  and the sport icon top-left over it, route overlaid with start/finish flag
  markers, and a bottom info card — sized to its content, no repo URL — holding
  the event title, date, and stats), and a slow 60fps animated video of the
  route drawing in over the same map. The map template's card title is the event name exactly as
  typed (casing preserved). Pace is shown without the ` /km` unit; speed
  sports keep `km/h`. Generated videos are temporary — share/save them before
  leaving, then they're cleaned up. Shared via the system share sheet.
- **GPX import** — `.gpx` file → activity (`source: gpx_import`).
- **Stats** — last-7-days distance chart + per-sport totals (distance, time,
  activity count), plus all-time totals and personal bests (longest distance,
  longest duration).
- **Sample data** — one-time seed (7 activities, all sports, last 7 days,
  organic random-walk paths) on first install so the app isn't empty. Users
  can delete everything; it never re-seeds (`seedSampleDataV1` flag).
- **Backup** — Profile → Export all as JSON to Files/**iCloud Drive**, and
  Import backup back (idempotent — existing ids are skipped). Event names
  round-trip through backups.
- **Profile** — a compact card (not a tall hero banner) with a fixed accent
  gradient (no custom cover photo) behind avatar/name/bio and a full-height
  darkening scrim so the gradient never reads as raw lime/blue, and the
  horizontal wordmark small top-trailing, always white in both light and
  dark mode. Appearance toggle is a compact icon-left/label-right control
  (System/Light/Dark), and a small version footer sits at the bottom.
- **Appearance** — light/dark/system toggle (icon picker), persisted.

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