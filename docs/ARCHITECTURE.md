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
`LogoHorizontal` is the Activities list's `.principal` toolbar item (replaces
the "Activities" title text entirely — a bare image in `.topBarLeading`
picks up iOS's "glass" toolbar chip background and looks like an accidental
button, so it's centered instead). On the Profile cover card it sits
top-trailing (where the now-removed cover-photo camera button used to be),
forced `.foregroundStyle(.white)` regardless of `colorScheme` — the cover's
gradient + darkening scrim are fixed brand colors now (no user photo), so the
wordmark no longer needs to adapt per appearance mode.

## Conventions

- `SWIFT_VERSION = 5.0` with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — Swift 6-style concurrency
  (main-actor-by-default) without full Swift 6 language mode.
- SwiftData + `@Observable`. `larpingApp` sets
  `.modelContainer(for: [CDActivity.self, CDTrackPoint.self])`. The single
  `ActivitiesStore` is created in `RootTabView` from
  `@Environment(\.modelContext)` and injected via `.environment(_:)`.
- `@Query` in `ActivitiesListView` keeps the list in sync automatically.
- No third-party dependencies. stdlib/SwiftUI/UIKit/MapKit/CoreLocation/HealthKit only
  (no PhotosUI — Profile has no photo upload, see below). System font
  everywhere (a bundled Domine font was tried and removed — the synchronized
  group does not copy `.ttf` resources).

## Layer map

```text
Core/
    Models/
      CDActivity.swift      SwiftData @Model — one activity (+ Time-Transient
                            computed pace/calories)
      CDTrackPoint.swift    SwiftData @Model — one GPS point (cascade with activity)
      Activity.swift        SportType enum, EventNamer (auto event-title numbering),
                            TrackPointPayload value type
  Location/
    LocationTracker.swift  CLLocationManager wrapper (one per recording)
  GPXParser.swift          stdlib XMLParser .gpx importer
  ShareImageComposer.swift 1080x1920 share card templates (Core Graphics + MapKit snapshot)
  ShareVideoComposer.swift AVAssetWriter-based animated route video export
  CameraCaptureView.swift  UIImagePickerController bridge (camera)
  BackupService.swift      JSON export + idempotent import (FileDocument)
  SeedData.swift           one-time sample activities (random-walk paths)
  Formatters.swift         distance/duration/pace/speed/elevation + ISO parse
  AppearanceMode.swift     light/dark/system toggle
  Health/
    HealthKitService.swift optional HealthKit interop — write: finished activity →
                          HKWorkout (+ route); read: recent HR samples,
                          workout routes (healthkit_import source).

Features/
  Root/          RootTabView — 4 tabs (Activities, Record, Stats, Profile),
                  SplashView — animated launch splash (logo, theme-aware)
  Record/        RecordView — live map, auto-save on finish, event name + auto-fill
  Activities/    ActivitiesListView (@Query), ActivityDetailView (hero map),
                  ImportGPXView, ImportHealthKitView, ShareActivityView, ActivitiesStore
  Stats/         StatsView — Swift Charts last-7-days + all-time + per-sport + personal bests
  Profile/       ProfileView — cover card (fixed gradient, no photo upload) + name/bio, appearance, backup export/import
```

## Data model

`CDActivity`: `id`, `sportTypeRaw`, `startedAt`/`endedAt`, `durationSeconds`
(**active/moving** time — pauses excluded; computed by `LocationTracker`, not
wall clock), `distanceMeters`, `elevationGainMeters`, `averageSpeedMps`, `maxSpeedMps`,
`source` (`mobile` | `gpx_import` | `healthkit_import` | `sample`), `eventName` (optional user title;
`EventNamer` ensures "Larping <Sport> N" auto names never collide), `createdAt`,
cascade `[CDTrackPoint]`.
`averagePaceSecondsPerKm`/`calories` are `@Transient` computed, as are
`maxHeartRateBpm`/`averageHeartRateBpm` (derived from track points; nil for
live recordings, populated for HealthKit imports).
`CDTrackPoint`: `timestamp`, `lat/lng`, `altitudeMeters`, `speedMps`, optional
heart rate/cadence (always nil today).

`EventNamer.nextName(base:existing:)` — given the auto base title ("Larping
Run") and the current event names, returns the base unchanged if it's unused,
otherwise bumps to the next free number (existing "Larping Run" → next is
"Larping Run 1"; holes and non-numeric suffixes are ignored). Live recorder
uses it both to auto-fill the field and to fill gaps left blank — recording the
same sport repeatedly never produces duplicate titles. Old/imported activities
with `eventName == nil` fall back to the base name at display time.
`ActivitiesStore.rename(_:to:)` lets a saved activity's event be renamed later
(detail view's overflow menu) — trims, and an empty result clears back to
`nil` (auto name) rather than storing an empty string.

No visibility, no cover photo — single-user offline app. The Profile cover
card cannot be customized with a photo (no `PhotosPicker`, no
`Documents/profile-cover.jpg`) — it's always the fixed accent→black gradient
with a darkening scrim.

## Startup & seeding

`larpingApp` shows a brief animated `SplashView` (logo wordmark, white in
dark / black in light mode over the `Canvas` background, ~1.4s then fades)
while booting. The static pre-SwiftUI launch screen is the same `Canvas`
background via `UILaunchScreen` in the explicit `Info.plist`, so the handoff
never flashes white/black.

`RootTabView.task` → `SeedData.seedIfNeeded(context:)` then creates +
refreshes `ActivitiesStore`. Seed inserts 7 activities (one per sport +
extra run) spread over the last 7 days with **random-walk loop paths**
(`SeedData.randomPath` — organic, steered back to center; no routing API),
guarded by the `seedSampleDataV1` UserDefaults flag so it runs on the first
install only and never re-seeds after the user deletes everything.

## Recording flow

`RecordView` owns a `@State LocationTracker`. Sport + event name are set in an
inline form before start (sport via a compact `Menu`, event via a text field
auto-filled by `EventNamer` and left editable) — **event name is required**,
trimmed-empty disables Start (with an inline hint) rather than silently
falling back at save time. The bottom control card is fully rounded
(`RoundedRectangle`, all corners) with horizontal/bottom margins so it floats
above the map instead of spanning edge-to-edge — matching the already-
transparent nav bar's floating look — and in dark mode is `Color.black.
opacity(0.75)` (was solid opaque black, then `.thinMaterial` before that,
which read as translucent gray over the map) — opaque enough to keep the
form legible, translucent enough that the map still shows through faintly;
light mode keeps `.thinMaterial`. On **Finish** it calls
`tracker.stop()`, then `ActivitiesStore.create(...)` **immediately** (auto-
save — no form, no discard path), storing the event name (auto name when left
blank), and shows a "saved" alert. Only after the local save succeeds does a
fire-and-forget `Task { await HealthKitService.saveWorkout(from: activity) }`
optionally mirror the workout into the Health app (see "HealthKit" below) —
HealthKit failure or denial never blocks or loses the local save.

**Active duration**: `startedAt`/`endedAt` keep true wall-clock timestamps,
but `durationSeconds` (and the pace/avg-speed it feeds) is **active time
only** — `LocationTracker` accumulates each recording interval at
start/pause/resume/finish boundaries (sub-second-precise `activeTime`, whole-
second `elapsedSeconds` for the on-screen timer). Pausing freezes both; a long
pause can never inflate a 20-minute run into 40. Stored this way,
live recordings, GPX, and HealthKit imports all carry a meaningful moving time. The recording header is a row — sport
bouncing icon left, event name right (no centered label). While **paused** the
header sport icon drops to `.secondary` color (bounce stops) and a small
`PAUSED` capsule appears next to it so the state is distinct at a glance;
recording never restarts until Resume. When the GPS fix degrades
(`horizontalAccuracy` invalid or `>= 50m`) during recording, points are
dropped as before but a small warning-colored "GPS signal weak" note appears
under the stat row (`LocationTracker.isGPSDegraded`, reset per recording) —
recording continues silently otherwise. Map is full-bleed
(`.ignoresSafeArea(edges: .top)`); the recenter control is a toolbar
top-trailing button (no default `mapControls`, which used to poke the status
bar). GPX import takes the same `create(...)` path from `GPXParser.Result`,
which also surfaces a sport auto-detected from the file's `<type>` element
(`GPXParser.sportType(from:)`, substring match, unknown → nil keeps the
picker default).

**Live rider marker**: while `tracker.state != .idle`, the default
`UserAnnotation()` blue dot is swapped for an `Annotation` at
`tracker.routeCoordinates.last` showing the selected sport's icon in an
accent-filled circle, bouncing while actively recording (paused stops the
bounce) — same visual language as the detail-view rider. Icon color is
`colorScheme`-dependent (black in dark mode, white in light mode) since the
accent fill is lime in dark mode — a white icon there had poor contrast.
Falls back to `UserAnnotation()` before a route exists.

**Nav/bar treatment**: Record is the immersive tab — the **top** nav bar has
no tint at all (transparent, map runs full-bleed behind the status bar; the
recenter button stays as a plain toolbar item). Instead the `Color.black.
opacity(0.75)` overlay moved to the **bottom tab bar** so the map's dark control
card reads as one block down to the tab bar. Applied with `.toolbarBackground`/
`.toolbarColorScheme(.dark, for: .tabBar)` but only from Record's own view
(scoped per-tab) — Activities/Stats/Profile keep the default liquid-glass tab
bar and their default nav bars. Light mode untouched (automatic).

**History heatmap**: the Record map draws every past activity's route
(`activitiesStore.activities`, capped at 500 by `ActivitiesStore.refresh`) as
a stacked translucent `MapPolyline` (`Color.accentColor.opacity(0.12)`)
underneath the live recording polyline. No real spatial-binning pass —
overlap "heat" is just alpha blending from stacking. Revisit with a proper
grid-binned intensity pass if the 50-activity cap or blending starts looking
wrong at higher activity counts.

**Route draw-in animation**: `ActivityDetailView.RouteMap` reveals the route
polyline progressively over ~5.5s using `TimelineView(.animation(paused:))`
— it slices `coordinates.prefix(revealedCount)` by elapsed-time fraction, so
it follows recorded point order (works for loops/backtracks, not just
point-to-point). A sport-specific icon marker (the activity's `symbolName`
in an accent-filled circle, `colorScheme`-dependent icon color, gently
bouncing while drawing — same styling as Record's live rider marker) rides
at the current tip
(`coordinates[revealedCount - 1]`), settling at the finish when the draw
completes. Paused after the draw completes so the timeline stops ticking.
`TimelineView` uses `.animation(minimumInterval: 1.0/12.0, paused:)` instead
of the default ~60fps schedule — at 60fps, `MapPolyline`'s overlay
reconciliation couldn't keep up with the tick rate, so the line stayed
visually static and only snapped in fully once ticking stopped (right when
the marker, which just repositions a lightweight `Annotation`, had already
reached the end) — looking like the line "popped in" after the fact instead
of drawing in sync. Throttling to ~12fps gives MapKit time to actually apply
each polyline update between ticks; `.animation(nil, value: revealedCount)`
stays on the `Map` so each throttled update still applies instantly rather
than cross-fading. The header overlay is icon bottom-left / event title + date
bottom-right (not a merged label) to use the otherwise-empty bottom-right
corner. Delete lives in the toolbar's overflow (`ellipsis.circle`) menu next
to Share, not a standalone button in the scrolling content — keeps a
destructive action from being the first prominent thing visible on open.

## Classic share template (`ShareImageComposer.compose(photo:coordinates:stats:routeRevealFraction:)`)

Canvas 1080x1920.

1. Background: photo full-bleed dimmed 48% black — or, with no photo, the
   **canvas is left transparent** so the exported plain card is a transparent
   PNG the user can paste onto anything (`ShareLink` shares a PNG). White
   foreground gets dark drop shadows only in the transparent mode so it stays
   legible over light pastes.
2. Small centered sport icon (box ~130pt, aspect-preserved) at top (starts
   at y≈190, extra top clearance for Instagram Story's own UI), with an
   offset dark backing when transparent.
3. `LogoHorizontal` wordmark (110pt tall, white 92%) centered right beneath
   the icon — now the dominant element (was smaller than the icon before;
   flipped so the brand mark reads first). No event title/date in the header
   anymore (moved to the footer, see below) — this template no longer names
   the event at all, just icon + brand mark.
4. Route: accent-color polyline (16pt, round joins) — `Accent` asset color
   resolved at draw time, so it follows system light/dark mode (lime dark,
   `#463CFF` light). Fits into an aspect-matched, centered region
   (y≈504..970) → symmetric margins for any route size.
5. Stats: one centered column, 3 rows (DISTANCE / DURATION / PACE).
6. Footer: the activity **date** (30 semibold, 72% white) — replaces the old
   repo URL text at the same position/size (y≈1610); the URL itself was
   dropped.

`drawHeader` lays out icon → logo with a running `cursorY` (each element's
`rect.maxY` + a fixed gap feeds the next), not hardcoded absolute y's for
every element — keeps the block self-consistent if any one piece's rendered
height varies.

## Map template (`ShareImageComposer.composeMapCard(snapshot:coordinates:stats:routeRevealFraction:)`)

Second template, and the frame renderer for the video. The map is no longer a
card-in-the-middle — a **full-canvas `MKMapSnapshotter` render** of the route's
bounding box fills the whole background (dimmed + a bottom gradient scrim),
with the route redrawn on top using the snapshot's `point(for:)` conversion
(exact, because the snapshot is requested at canvas size → 1:1 mapping). The
`LogoHorizontal` wordmark floats **top-right over the map itself** (52pt,
dark backing so it stays legible over unpredictable map colors, y≈170); the
sport icon mirrors it **top-left** (44pt, same dark backing, y≈170) — both
live outside the card so it reads as marks on the photo, not card content,
and so the card's title/date can start flush left instead of being indented
past an icon. Both sit lower than a naive top corner (y≈170, not 90) so
Instagram Story's own profile-chip/close-button overlay doesn't cover them.
The **bottom card** (y≈1180..1560, sized to its content instead of a fixed
oversized box that left empty space) holds event title + date and the three
stats — no icon, no repo URL, no separator line (removed for a cleaner
look; date text shrunk to 30pt/72% white to match the classic template's
footer date). Card background dropped from 72% to 50% black opacity (was
reading too dark/opaque) and corner radius bumped 32→48 to match the
roundedness of the Record bottom card. No snapshot available (offline) →
falls back to space-black background + the same card (+ top-left icon,
top-right wordmark). `routeRevealFraction` (0...1) draws only the leading
portion of the route with a dot at the tip, used by video frames; once fully
revealed (static image), small flag badges mark the route's start and
finish points instead.

## Video template (`ShareVideoComposer.composeVideo(snapshot:coordinates:stats:)`)

Third template: an `AVAssetWriter`-encoded MP4, 1080x1920, 60fps, 6s. The map
snapshot is fetched **once**, then `composeMapCard(...routeRevealFraction:)`
re-renders each frame with the route progressively revealed — still just one
map-tile fetch for the whole export (deliberately not a live map per frame,
which would mean hundreds of network calls). Output goes to
`FileManager.temporaryDirectory`; `ShareActivityView` deletes it on dismiss so
nothing accumulates — the user must save/share it after generating.

`ShareActivityView`: three templates in a `TabView(.page)` (preview area
640pt tall) — classic (photo or transparent plain background, renders on
open), map (async, loads shortly after open), video (renders on demand
only). The classic template's transparent (photo-less) preview sits on a
black backing purely for on-screen visibility in light mode — the black is
preview-only, the composed/shared/saved `UIImage` stays fully transparent.
Camera | Gallery | "Plain background ×" only show for the classic template,
placed **below** the Share button so swiping templates never reshuffles
them. Preview taps open a full-screen zoom (always on a black backdrop). A
tap-through of the thumbnail and full-screen share preview is web-free, all
Core Graphics.

## Activities list & Stats enrichment

`ActivitiesListView` is no longer a flat list: a "This week" stat strip
(distance/time/count, same shape as `StatColumn`) sits above the rows, and
activities are grouped into `Section`s by month (`Dictionary(grouping:)` on
a `"MMMM yyyy"`-formatted key, sections sorted newest-first). Each row's
title is the event name (falls back to the sport label) instead of the
generic sport label, matching how Detail/Share already prioritize the event
title.

`StatsView` keeps the last-7-days chart + per-sport section (now also shows
total time, activity count, and max heart rate per sport when any activity
carries one) and adds two all-time sections: raw totals
(distance/time/activity count across everything ever recorded) and "Personal
bests" (longest single-activity distance, longest single-activity duration,
and highest max heart rate, each with their sport icon).

## Backup / restore

`BackupService.backupFile(from:)` flattens `CDActivity`+points into plain
Codable snapshots (`BackupContainer { app:"Larping", version:1, ... }`, pretty
JSON, ISO dates) → system `fileExporter` (Files/iCloud Drive/Mail).
`BackupService.restore(from:into:)` decodes the same shape and re-materializes
records, **skipping ids that already exist** (idempotent — never duplicates
or deletes) and rejecting junk/non-Larping files. `ProfileView` has both
"Export all activities" and "Import backup", and stamps `@AppStorage
"lastBackupDate"` on each success — shown in the Backup section as
"Last backup: …".

## HealthKit write layer

Optional interop, deliberately decoupled: **SwiftData stays the source of
truth**, HealthKit is a best-effort mirror. `Core/Health/HealthKitService.swift`
(single `enum`, no protocols — matches `BackupService`/`GPXParser` shape)
provides availability, auth, and `saveWorkout(from:)`. Profile gains a
"Health" section (only when `HKHealthStore.isHealthDataAvailable()`) with an
"Allow HealthKit access" button calling `requestAuthorization()`; authorized
state reads `authorizationStatus(for: .workoutType())`.

`saveWorkout(from:)` guards on availability + share authorization, builds an
`HKWorkout` (sport mapped via `HKWorkoutActivityType(sport:)`, duration,
GPS distance) then `HKWorkoutRouteBuilder.insertRouteData` +
`finishRoute(with:)` for the polyline. Route samples re-report accuracy at the
recorder's accepted ceiling (50m horizontal — never overstated; the recorder
drops worse fixes). Active energy is deliberately not written — Larping's
calorie value is a crude formula and isn't worth putting into Health as
measured data. The write uses the `HKWorkout(activityType:start:end:...)`
initializer (deprecated in iOS 17 in favor of `HKWorkoutBuilder`) — the
builder targets live session collection and is far more machinery than a
post-hoc write warrants; the deprecated init remains fully functional.

## HealthKit read / import

`requestAuthorization` also asks read access for workouts, routes, and heart
rate. `ActivitiesListView`'s Import toolbar became a `Menu` (GPX +
"Import from Health"), presenting `ImportHealthKitView` when
`HKHealthStore.isHealthDataAvailable()`. The import sheet shows the most
recent Health workouts (`fetchRecentWorkouts`); choosing one lets the sport
type be overridden and shows a summary, then Import materializes it through
the same `ActivitiesStore.create` path as GPX with `source: "healthkit_import"`
and an `eventName` auto-name from `EventNamer`.

Route polyline (`fetchRoute`, empty workouts import as metadata-only) and
heart rate (`heartRateSamples`, oldest→newest, matched to each track point at
or before its timestamp, `heartRateBpm` filled when available) come along
when the Health store has them. Distance prefers `HKWorkout.totalDistance`,
else sums the route; elevation/max speed derive from the route. Fallbacks:
HealthKit unavailable → the menu entry and sheet prompt are hidden;
authorization denied → explanation + "Open Settings" (or "Allow HealthKit
access" while notDetermined); no workouts → `ContentUnavailableView` empty
state. Nothing is fabricated when route/HR are missing.

## Info.plist gotchas

`GENERATE_INFOPLIST_FILE = YES` plus an explicit `larping/Info.plist` merged
via `INFOPLIST_FILE` (contains `UIBackgroundModes: [location]`). Reason:
array-typed keys like `UIBackgroundModes` are NOT synthesized by generic
`INFOPLIST_KEY_*`; the explicit file needs a
`PBXFileSystemSynchronizedBuildFileExceptionSet` (`membershipExceptions =
Info.plist, larping.entitlements`) or Xcode would also copy it as a bundle
resource. It also carries `UILaunchScreen` (`UIColorName = Canvas`) so the
static launch screen matches the animated splash's color in both modes.
Scalar keys (NSCameraUsageDescription, NSPhotoLibraryAddUsageDescription,
NSLocationAlwaysAndWhenInUseUsageDescription, NSHealthShareUsageDescription,
NSHealthUpdateUsageDescription) work via build settings. HealthKit capability:
`com.apple.HealthKit` in target `SystemCapabilities` +
`larping/larping.entitlements` (`com.apple.developer.healthkit`) referenced by
`CODE_SIGN_ENTITLEMENTS` — excluded from the synced group like `Info.plist`.

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