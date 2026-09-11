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
| `Accent` + `AccentColor` | `#463CFF` | `#CEFE06` | System tint — adaptive brand color |

**Contrast rule for prominent buttons** (Start/Share use the accent as
background): their label foreground is chosen from `colorScheme` — white in
light mode (readable on `#463CFF`), black in dark mode (readable on lime).
Destructive buttons (Finish) must NOT get that override — iOS renders them
red-background/white-text natively.

**Logo assets** (`Assets.xcassets`): `AppIcon.appiconset` (light/dark/tinted,
1024x1024, generated from the square mark) and `LogoHorizontal.imageset`
(wordmark, `template-rendering-intent: template` — single alpha-mask PNG,
recolor per-placement with `.foregroundStyle`/`.tintColor` rather than
shipping separate black/white files). Both are derived from `logo.png` /
`logo-horizontal.png` at the repo root, which are raw, oversized design
sources — never reference them directly from app code; regenerate the
in-bundle assets from them instead if the source logo changes.
`LogoHorizontal` is shown top-left of the Activities list toolbar.

## Conventions

- `SWIFT_VERSION = 5.0` with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — Swift 6-style concurrency
  (main-actor-by-default) without full Swift 6 language mode.
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
  Profile/       ProfileView — banner + name/bio, appearance, backup export/import
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

**History heatmap**: the Record map draws every past activity's route
(`activitiesStore.activities`, capped at 50 by `ActivitiesStore.refresh`) as
a stacked translucent `MapPolyline` (`Color.accentColor.opacity(0.12)`)
underneath the live recording polyline. No real spatial-binning pass —
overlap "heat" is just alpha blending from stacking. Revisit with a proper
grid-binned intensity pass if the 50-activity cap or blending starts looking
wrong at higher activity counts.

**Route draw-in animation**: `ActivityDetailView.RouteMap` reveals the route
polyline progressively over ~5.5s using `TimelineView(.animation(paused:))`
— it slices `coordinates.prefix(revealedCount)` by elapsed-time fraction, so
it follows recorded point order (works for loops/backtracks, not just
point-to-point). A small accent-colored dot marker rides at the current tip
(`coordinates[revealedCount - 1]`), standing in for "the person"; could
become a sport-specific icon later. Paused after the draw completes so the
timeline stops ticking.

## Share card (`ShareImageComposer.compose(photo:coordinates:stats:routeRevealFraction:)`)

Canvas 1080x1920, white text on a space-dark background regardless of the
app's own light/dark theme; only the route line uses the adaptive brand
accent:

1. Background: photo full-bleed dimmed 48% black, or `spaceBlack` (#0E1115).
2. Big centered sport icon (box ~230pt, aspect-preserved) at top.
3. Centered "LARPING <SPORT>" (54 heavy) + date (40 semibold, 78% white).
4. Route: accent-color polyline (16pt, round joins) — `Accent` asset color
   resolved at draw time, so it follows system light/dark mode (lime dark,
   `#463CFF` light) even though the card background never changes. Fits into
   a region whose aspect matches the route bbox, centered in the available
   area (y≈560..970) → **symmetric margins** for any route size.
   `routeRevealFraction` (0...1, default 1) draws only the leading portion in
   recorded point order with a dot marker at the tip — used by the video
   export template; the static image always passes 1 (no dot).
5. Stats: one centered column, 3 rows (DISTANCE / DURATION / PACE), system
   font: labels 34 medium 62% white, values 64 heavy monospaced.
   Pace value has the ` /km` suffix stripped (pace is always per-km); speed
   sports keep `km/h`. The strip happens in `ShareActivityView.stats`, not the
   composer.
6. Footer: `LogoHorizontal` wordmark centered at y≈1560 (44pt tall, white
   85%) with the repo URL right below it — deliberately above Instagram
   Story's reply-input area. Replaced the old plain-text "Larping · actually
   works" watermark.

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

## Tests

`larpingTests/` has real unit coverage for the non-trivial logic:
`GPXParserTests`, `FormattersTests`, `BackupServiceTests` (round-trip via an
in-memory `ModelContainer`), `ShareImageComposerTests` (canvas-size smoke
test). `larpingUITests/` is still the unmodified Xcode template scaffold
(launch test only). Run via Xcode's Test navigator or:

```bash
xcodebuild -project larping.xcodeproj -scheme larping \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```