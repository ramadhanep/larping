# Larping iOS — Architecture

SwiftUI app, iOS, Xcode project at `larping.xcodeproj` (uses the modern
`PBXFileSystemSynchronizedRootGroup` — files dropped into `larping/`
automatically join the build, no project edits needed). Brand "Larping" /
tagline "actually works".

**Offline-first, zero networking.** Fully local via SwiftData. The original
NestJS-backed architecture was removed (see `STATUS.md` for history).

## Theme & branding

Black/white monochrome (Grok-style). Colors defined entirely as
Assets.xcassets color sets with Any/Dark variants; Xcode synthesizes
`Color.ink`, `.canvas`, `.cardSurface`, `.slate`, `.muted`, `.border`, etc.

| Set | Light | Dark | Use |
|---|---|---|---|
| `Ink` | `#0F1115` | `#FAFAFA` | Primary text/icons (swaps with Canvas) |
| `Canvas` | `#FAFAFA` | `#0F1115` | Main background |
| `CardSurface` | `#FFFFFF` | `#242A33` | Elevated surfaces |
| `Slate` | `#242A33` | `#242A33` | Fixed dark tone |
| `Muted` | `#6B7280` | `#9CA3AF` | Secondary text |
| `Border` | `#E5E7EB` | `#374151` | Borders |
| `Success`/`Error`/`Info`/`Warning` | `#22C55E`/`#EF4444`/`#3B82F6`/`#F59E0B` | same | Status |
| `Accent` + `AccentColor` | `#000000` | `#FFFFFF` | System tint (adaptive monochrome) |

**Contrast rule for prominent buttons** (Start/Resume/Share use the
monochrome accent as background): their label is forced to `.foregroundStyle
(Color.canvas)` so text stays readable in both modes (black text on white
button in dark mode). Destructive buttons (Finish) must NOT get that override
— iOS renders them red-background/white-text natively.

Per-sport color sets (`Sport*`) are dead assets (unused).

## Conventions

- Swift 6 concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- SwiftData + `@Observable`. `larpingApp` sets
  `.modelContainer(for: [CDActivity.self, CDTrackPoint.self])`. The single
  `ActivitiesStore` is created in `RootTabView` from
  `@Environment(\.modelContext)` and injected via `.environment(_:)`.
- `@Query` in `ActivitiesListView` keeps the list in sync automatically.
- No third-party dependencies. stdlib/SwiftUI/UIKit/MapKit/CoreLocation/
  PhotosUI only. System font everywhere (a bundled Domine font was tried and
  removed — the synchronized group does not copy `.ttf` resources).

## Layer map

```text
Core/
  Models/
    CDActivity.swift      SwiftData @Model — one activity (+ Time-Transient
                          computed pace/calories)
    CDTrackPoint.swift    SwiftData @Model — one GPS point (cascade with activity)
    Activity.swift        SportType enum + TrackPointPayload value type
  Location/
    LocationTracker.swift  CLLocationManager wrapper (one per recording)
  GPXParser.swift          stdlib XMLParser .gpx importer
  ShareImageComposer.swift 1080x1920 share card (Core Graphics)
  CameraCaptureView.swift  UIImagePickerController bridge (camera)
  BackupService.swift      JSON export + idempotent import (FileDocument)
  SeedData.swift           one-time sample activities (random-walk paths)
  Formatters.swift         distance/duration/pace/speed/elevation + ISO parse
  AppearanceMode.swift     light/dark/system toggle

Features/
  Root/          RootTabView — 4 tabs (Activities, Record, Stats, Profile)
  Record/        RecordView — live map, auto-save on finish
  Activities/    ActivitiesListView (@Query), ActivityDetailView,
                  ImportGPXView, ShareActivityView, ActivitiesStore
  Stats/         StatsView — Swift Charts last-7-days + per-sport
  Profile/       ProfileView — name/bio, appearance, backup export/import
```

## Data model

`CDActivity`: `id`, `sportTypeRaw`, `startedAt`/`endedAt`, `durationSeconds`,
`distanceMeters`, `elevationGainMeters`, `averageSpeedMps`, `maxSpeedMps`,
`source` (`mobile` | `gpx_import` | `sample`), `createdAt`, cascade
`[CDTrackPoint]`. `averagePaceSecondsPerKm`/`calories` are `@Transient`
computed. `CDTrackPoint`: `timestamp`, `lat/lng`, `altitudeMeters`,
`speedMps`, optional heart rate/cadence (always nil today).

No visibility, no cover photo — single-user offline app.

## Startup & seeding

`RootTabView.task` → `SeedData.seedIfNeeded(context:)` then creates +
refreshes `ActivitiesStore`. Seed inserts 7 activities (one per sport +
extra run) spread over the last 7 days with **random-walk loop paths**
(`SeedData.randomPath` — organic, steered back to center; no routing API),
guarded by the `seedSampleDataV1` UserDefaults flag so it runs on the first
install only and never re-seeds after the user deletes everything.

## Recording flow

`RecordView` owns a `@State LocationTracker`. On **Finish** it calls
`tracker.stop()`, then `ActivitiesStore.create(...)` **immediately** (auto-
save — no form, no discard path), and shows a "saved" alert. Sport selected
before start; visibility no longer exists. Map is full-bleed
(`.ignoresSafeArea(edges: .top)`); the recenter control is a toolbar
top-trailing button (no default `mapControls`, which used to poke the status
bar). GPX import takes the same `create(...)` path from `GPXParser.Result`.

## Share card (`ShareImageComposer.compose(photo:coordinates:stats:)`)

Canvas 1080x1920, pure white-on-black, system font, no card/logo/brand color:

1. Background: photo full-bleed dimmed 48% black, or `spaceBlack` (#0E1115).
2. Big centered sport icon (box ~230pt, aspect-preserved) at top.
3. Centered "LARPING <SPORT>" (54 heavy) + date (40 semibold, 78% white).
4. Route: white polyline (16pt, round joins), early-16th scale — fits into a
   region whose aspect matches the route bbox, centered in the available area
   (y≈560..970) → **symmetric margins** for any route size. No endpoint dots.
5. Stats: one centered column, 3 rows (DISTANCE / DURATION / PACE), system
   font: labels 34 medium 62% white, values 64 heavy monospaced.
   Pace value has the ` /km` suffix stripped (pace is always per-km); speed
   sports keep `km/h`. The strip happens in `ShareActivityView.stats`, not the
   composer.
6. Footer centered at y≈1580 ("Larping · actually works", 34 bold) and
   y≈1638 (`github.com/ramadhanep/larping`, 30 semibold) — deliberately above
   Instagram Story's reply-input area.

`ShareActivityView`: renders the plain card immediately on open; Camera |
Gallery buttons, then a plain-text "Plain background ×" link (shown only when
a photo is set), then the Share button.

## Backup / restore

`BackupService.backupFile(from:)` flattens `CDActivity`+points into plain
Codable snapshots (`BackupContainer { app:"Larping", version:1, ... }`, pretty
JSON, ISO dates) → system `fileExporter` (Files/iCloud Drive/Mail).
`BackupService.restore(from:into:)` decodes the same shape and re-materializes
records, **skipping ids that already exist** (idempotent — never duplicates
or deletes) and rejecting junk/non-Larping files. `ProfileView` has both
"Export all activities" and "Import backup".

## Info.plist gotchas

`GENERATE_INFOPLIST_FILE = YES` plus an explicit `larping/Info.plist` merged
via `INFOPLIST_FILE` (contains `UIBackgroundModes: [location]`). Reason:
array-typed keys like `UIBackgroundModes` are NOT synthesized by generic
`INFOPLIST_KEY_*`; the explicit file needs a
`PBXFileSystemSynchronizedBuildFileExceptionSet` (`membershipExceptions =
Info.plist`) or Xcode would also copy it as a bundle resource. Scalar keys
(NSCameraUsageDescription, NSPhotoLibraryAddUsageDescription,
NSLocationAlwaysAndWhenInUseUsageDescription) work via build settings.

## Build & verify

```bash
xcodebuild -project larping.xcodeproj -scheme larping \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build \
  2>&1 | grep -Ei "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

Delete `~/Library/Developer/Xcode/DerivedData/larping-*` when testing
schema-affecting changes, and uninstall the app if the persistent store
schema changed (see `KNOWN_ISSUES.md`).