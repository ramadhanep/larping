# iOS App — Status Log

Chronological build history in commit order. For "what it looks like now" read
`ARCHITECTURE.md`; this file is "how it got here" and the reasoning behind
non-obvious fixes. `git log --oneline` for exact diffs.

## Pre-refactor era (API-backed, all since superseded)

Commits `4d45766`→`7674b43` built the original **server-backed** app: auth
(login/register + JWT session), `APIClient`/`SessionStore`, activity
list/detail against the NestJS API, S3 cover-photo upload, background
recording, an offline retry queue (`PendingActivityQueue`), Stats tab, GPX
import, and the share feature. Notable root-cause fixes preserved for context:

- `cc7209a` — `UIBackgroundModes` is array-typed and `INFOPLIST_KEY_*`
  doesn't synthesize it → explicit merged `Info.plist` +
  `PBXFileSystemSynchronizedBuildFileExceptionSet`. (Still applies today.)
- `18cae6f` — client-only `id` field inside a request body was 400-rejected
  by the backend's `forbidNonWhitelisted` ValidationPipe → keep local-only
  fields out of network request types. (Moot now — no networking.)

## `d40a648` — Offline-first rewrite: SwiftData, zero API

The pivot. Removed `APIClient`, `APIError`, `KeychainStore`, `UploadService`,
`SessionStore`, `Auth/Upload/User` models, `PendingActivityQueue`,
`LoginView`, `RegisterView`. Added SwiftData `CDActivity`/`CDTrackPoint`,
`.modelContainer` wiring, and rewrote `ActivitiesStore` as local CRUD.
`RecordView` **auto-saves on finish** (no form/discard). Dropped cover photos
and the visibility picker. `ProfileView` became local (`@AppStorage`).
`Accent`/`AccentColor` made adaptive monochrome.

## `aa3b310` — Share card: "LARPING <sport>" header

Icon-left-of-title header, repo URL footer. (Layout superseded by `88cb77e`;
the LARPING prefix + footer stuck.)

## `8919504` — Backup export + docs rewritten

`BackupService.backupFile` → system `fileExporter` (saves to Files / iCloud
Drive). All docs rewritten to the offline-first reality.

## `90efbe9` — Backup import/restore + share layout tweaks

`BackupService.restore` (idempotent, skips existing ids, rejects junk) +
Profile "Import backup" with confirmation dialog. Share: no endpoint dots,
icon aligned to title line, stats as one column, footer raised above the IG
reply bar; share view renders plain background on open, Camera|Gallery row +
plain-bg link + share button.

## `c2d307a` — Monochrome button contrast, icon stretch fix

Default Apple-contrast failed on white accent → prominent button labels forced
`Color.canvas`. Share icon was stretched into a square box → aspect-preserved.
Record map stopped ignoring top safe area at the time. Domine font embedded
as base64 for the share overlay.

## `60e8ca0` — Drop Domine, fix destructive text, location button to header

Domine removed (SDK's synced group won't bundle `.ttf`; system font instead).
**Destructive Finish buttons keep native red+white text** (no `Color.canvas`
override — that made black text on red). Record map restored to full-bleed
top; the default `MapUserLocationButton` dropped for a
toolbar top-trailing "location" button aligned with the nav bar. Route drawn
into an **aspect-matched box centered** in the share area (symmetric margins
for any route size).

## `68cdc77` — Seed sample data + remove duplicate location button

`SeedData` seeds one-time sample activities (7, all sports, last-7-days,
random-walk loop paths) guarded by the `seedSampleDataV1` UserDefaults flag —
never re-seeds after the user deletes everything. Removed the leftover default
`MapUserLocationButton` (was double with the toolbar one).

## `88cb77e` — Bolder stat tiles, organic seed paths, share header on top

- `ActivityDetailView` stat values: `.title3.monospacedDigit().bold()`.
- Seed paths: random-walk (drifting heading, steered to center), not circles.
- Share header: **big centered sport icon on top**, smaller "LARPING <SPORT>"
  (54 heavy) + date beneath it.
- Share pace value loses the redundant ` /km` (speed sports keep `km/h`);
  the strip lives in `ShareActivityView.stats`.

## Uncommitted — Event names, live profile cover, redesigned share templates

A broad UX pass across Record / Profile / Share / Detail:

- **Event names.** `CDActivity.eventName` (optional `String` — lightweight
  migration; also round-trips through backups). `RecordView` auto-fills the
  field as `Larping <Sport>` and bumps to `… 1`, `… 2` whenever that exact name
  already exists (`EventNamer.nextName(base:existing:)` — matching titles only,
  non-numeric suffixes ignored). Blank field → auto name at save time. Share
  cards and the detail hero use the event title with **casing preserved**
  instead of a forced "LARPING <SPORT>".
- **Profile** became a cover banner: accent→black gradient (or user photo via
  PhotosPicker, persisted to `Documents/profile-cover.jpg`) with the avatar/
  name/bio over a dark scrim, the horizontal wordmark small at top-leading
  (black in dark mode on the lime accent, white in light — a translucent chip
  backs it when a photo is set), animated bouncing avatar. The appearance
  segmented picker was replaced by an icon+label control
  (System/Light/Dark, `AppearanceMode.symbolName`). The "About" section is
  gone; a small "Larping vX.Y (N)" footer sits bottom-centered (from
  `CFBundleShortVersionString`).
- **Share templates reworked.** Classic card with no photo exports a
  **transparent PNG** (white content + dark shadows → pasteable anywhere).
  The map template flipped its layout: full-canvas map snapshot as the
  *background* (dimmed + bottom scrim), route overlaid, and a bottom
  info-card holding title/date/stats/logo/URL. The **video** renders the same
  map design: one snapshot fetched once, then
  `composeMapCard(...routeRevealFraction:)` per frame — no per-frame tile
  fetches. Video lives in `temporaryDirectory` and is **deleted on sheet
  dismiss** (must save/share right away). Previews are bigger and tap to
  open full-screen; camera/gallery sit *below* the Share button so swiping
  templates doesn't reshuffle controls.
- **Detail map** is now a hero: taller route map with the title/date overlaid
  on a scrim and a bouncing sport-symbol rider at the draw tip.
- Icons animate in place via `symbolEffect(.bounce)` (run/cycle/walk glyphs
  — no GIFs needed): profile avatar, record header while recording, detail
  map rider.

Root causes worth remembering:
- Map-bg video must fetch the snapshot once, not per frame (the old video used
  the non-map composer; a per-frame map would be ~360 tile fetches per export).
- Full-bleed map drawing stays aligned because the snapshot is requested at
  `canvasSize`, making `MKMapSnapshotter.point(for:)` a 1:1 canvas mapping.

### Follow-up pass — fixed items an earlier attempt at this same work skipped

- **Profile cover overlap bug.** The wordmark chip and the name/bio block were
  each independently bottom-pinned inside the `ZStack` with their own fixed
  `.padding(.bottom, ...)` — on a short bio they landed ~8pt into each other.
  Rebuilt as one `VStack` (`Spacer()` + info + logo row) so the logo can never
  overlap the info block regardless of content length. Scrim changed from
  top-`.clear`→bottom-black to a 3-stop gradient that darkens the *whole*
  cover, so the accent-gradient fallback (no photo set) never shows a patch of
  raw, undimmed lime/blue.
- **Appearance picker** — bigger icon (17→22pt), label (`.caption`→
  `.subheadline`), padding, and corner radius.
- **Activities toolbar circle.** A bare `Image` in `.topBarLeading` picks up
  iOS's "glass" toolbar chip background by default, making the wordmark look
  like an accidental button. Fix: drop the "Activities" title text and use the
  wordmark as the `.principal` toolbar item instead (no leading slot at all).
- **Record map had no rider.** Swapped the default `UserAnnotation()` for a
  sport-icon marker at the live route's last coordinate whenever
  `tracker.state != .idle` (falls back to the blue dot before a route exists)
  — same visual language as the detail-view rider.
- **Detail view: route line lagging the rider marker.** Both were driven by
  the same `revealedCount` each `TimelineView` tick, but MapKit implicitly
  animates polyline geometry changes while the annotation snaps immediately —
  so the marker visibly ran ahead and the line caught up after the fact.
  Fixed with `.animation(nil, value: revealedCount)` on the `Map`.
  Also moved event title + date to the hero map's bottom-right (previously
  empty) with the sport icon alone bottom-left, instead of a single merged
  label crowding one corner.
- **Delete UX.** Was a plain destructive-red link floating below the stat
  grid — reads as the most prominent thing on the screen the moment you open
  an activity. Moved into the toolbar's `ellipsis.circle` overflow menu
  alongside Share (a deliberate extra tap before anything destructive is even
  visible); the confirmation dialog now names the activity being deleted.
- **Share: wordmark barely visible.** Classic template: wordmark moved from a
  small 44pt footer mark (buried below three stat rows) to directly under the
  sport icon at 56pt, using a running `cursorY` layout so title/date/route
  shift down to make room. Map template: wordmark moved out of the info card
  entirely to float top-right over the map itself at 52pt with a dark
  backing (was 30pt, inline in the card, easy to miss); the repo URL stays in
  the card.
- **Share: transparent classic card invisible in light mode.** The photo-less
  card is intentionally a transparent PNG (white content) — previewed
  directly on the sheet's background, it disappeared entirely in light mode.
  Preview now sits on a black backing (preview-only; the actual composed/
  shared/saved image is unchanged, still transparent).
- **Share preview area enlarged** 560pt → 640pt across all three templates
  (was the same complaint for all of them, not just video — one shared
  `TabView` height, so one fix covers all three).

### Follow-up pass 2 — profile card felt like a literal cover photo, record polish, rename

- **Profile card overcorrected.** The first pass's 330pt banner still read as
  a literal "cover photo" hero. Shrunk to a 170pt wide card (avatar 72→46pt,
  no `symbolEffect` bounce — a constantly-animating icon on a settings-ish
  screen read as anxiety-inducing, not lively), wordmark moved to
  bottom-center at 14pt, and the camera/remove-cover button moved to a small
  top-trailing circle now that the bottom is reserved for the centered
  wordmark.
- **Appearance picker shrunk back down.** Icon+label stacked in a `VStack`
  made each option a big square tile. Changed to icon-left/label-right in an
  `HStack` (13pt icon, footnote text, 8pt vertical padding) — reads as a
  compact segmented control, not three large buttons.
- **Rename event.** `ActivitiesStore.rename(_:to:)` (trims, empty → nil so it
  falls back to the auto name) + an alert with a `TextField` from the detail
  view's overflow menu, alongside Share/Delete.
- **Record bottom control card.** `UnevenRoundedRectangle(topLeadingRadius:
  topTrailingRadius:)` so only the top corners round (matches the sheet/card
  language used everywhere else instead of a hard-edged bar). Background is
  solid `Color.black` in dark mode instead of `.thinMaterial` (which reads as
  translucent gray over the map) — light mode keeps `.thinMaterial`. The
  idle sport-picker + event-name row is bigger (14pt padding, 14pt corner
  radius, matching the appearance-toggle/card radius language) and the event
  field is now **required** — trimmed-empty blocks Start (with an inline
  hint), not just an auto-filled suggestion you could clear before hitting
  Start.

### Follow-up pass 3 — floating record card, cover-photo removal, real animation fix, richer Activities/Stats

- **Record bottom card floats over the map.** Was top-corners-only,
  edge-to-edge. Changed to a full `RoundedRectangle` with horizontal + bottom
  margins so it visually floats above the map, matching the already-
  transparent nav bar.
- **Profile cover-photo upload removed entirely.** No more `PhotosPicker`,
  `coverImage`/`coverPickerItem` state, `Documents/profile-cover.jpg`
  read/write, or camera/remove buttons — the cover is always the fixed
  accent→black gradient + scrim. The horizontal wordmark moved from
  bottom-center to top-trailing (where the camera button sat) and is now
  hardcoded `.foregroundStyle(.white)` for both light and dark mode, since
  the cover no longer changes color per photo/appearance.
- **Route-draw animation, actually fixed this time.** The prior
  `.animation(nil, value: revealedCount)` fix (pass 1) didn't address the
  real cause: `TimelineView(.animation(paused:))` ticks at ~60fps by default,
  and `MapPolyline`'s overlay reconciliation is too slow to keep up — so the
  line stayed visually static and only appeared, fully drawn, the instant
  ticking stopped (right as the lightweight `Annotation` marker, which only
  repositions and doesn't hit this bottleneck, had already reached the end).
  Fixed by throttling the schedule to `minimumInterval: 1.0/12.0`, giving
  MapKit time to actually apply each polyline update between ticks so the
  line now visibly draws in step with the marker.
- **Activities list enriched.** A "This week" distance/time/count strip sits
  above the list; activities are grouped into month `Section`s instead of one
  flat list; row titles now show the event name (falls back to sport label),
  matching Detail/Share.
- **Stats enriched.** Per-sport rows now show total time and activity count
  alongside distance. Added all-time totals (distance/time/count) and a
  "Personal bests" section (longest single-activity distance, longest
  single-activity duration).

### Follow-up pass 4 — Record card overlay, classic/map share template cleanup

- **Record bottom card is a translucent overlay, not solid black.** Dark mode
  background changed to `Color.black.opacity(0.75)` (was fully opaque) so the
  map shows through faintly while the form stays legible.
- **Classic share template dropped the event title.** The date moved into
  the footer at the same size/position the repo URL used to occupy, and the
  URL text itself was removed. The route's available area grew (504..970 vs
  580..970) to use the vertical space freed by removing the header's
  title/date block.
- **Map share template: icon moved top-left over the map** (mirroring the
  wordmark's top-right placement) so the info card's title/date can sit flush
  left instead of indented past an icon. The card's repo-URL footer was
  removed and its height shrunk from a fixed 580 (leaving empty space below
  the stats row) to 380, sized to its actual content. Card background alpha
  dropped 0.72→0.5 (was reading too dark) and corner radius bumped 32→48 to
  match the Record card's roundedness.

### Follow-up pass 5 — marker consistency, Record nav tint, share template polish

- **Sport marker icon color fixed for dark mode.** The accent background is
  lime in dark mode, so a white icon on top had poor contrast — icon color is
  now `colorScheme == .dark ? .black : .white`. Applied to both the live
  Record marker and Activity Detail's `RouteMap` marker, which also switched
  its background from a static `.black.opacity(0.6)` to `.accent` to match
  Record exactly.
- **Record's nav bar now tints black in dark mode** via
  `.toolbarBackground(Color.black.opacity(0.75), for: .navigationBar)` +
  `.toolbarColorScheme(.dark, for: .navigationBar)` (dark mode only) so the
  liquid-glass bar matches the black card overlay below it instead of
  rendering a mismatched light glass. Light mode is untouched.
- **Classic share template: icon/logo proportions reversed.** Icon shrunk
  230→130pt, wordmark grown 56→110pt (logo is now the dominant element), and
  header start `cursorY` moved 110→190 for more top clearance when shared to
  Instagram Story (avoids the profile chip/close button overlay).
- **Map share template date text matches the classic footer's style** (32pt
  @0.8 alpha → 30pt @0.72 alpha). The card's separator line was removed
  entirely (no `drawCardDivider` call left; the now-unused function was
  deleted) for a cleaner look. The top-right logo and top-left icon both
  moved down (`y: 90` → `y: 170`) so Instagram Story's own overlay doesn't
  cover them.
- **Map share template gets start/finish markers.** `drawRoute(onto
  snapshot:...)` now draws a small white-outlined badge with a flag glyph at
  the route's first and last points once the route is fully revealed (static
  image / finished state only — the video's in-progress leading dot is
  unchanged).
- **Apple Maps attribution cannot be hidden.** Apple's MapKit terms require
  the logo/legal attribution to stay visible on any map view; there is no
  compliant API to remove it, so this was intentionally left as-is (see
  `docs/KNOWN_ISSUES.md`).

## `(pending)` — Record correctness pass: product name, fetch cap, GPS + pause feedback

- **Product-name fix.** Location permission strings said "LarpingRun"
  (old working title) — all four `INFOPLIST_KEY_NSLocation*UsageDescription`
  values in both Debug/Release build configs now say "Larping".
- **ActivitiesStore fetch cap raised.** `refresh()` was capped at 50 most-
  recent activities, silently dropping older ones from the Record history
  heatmap. Now 500 — bounded enough to keep the heatmap from piling up
  hundreds of routes while covering realistic activity counts. (The
  Activity list itself never had this problem — it's `@Query`-driven.)
- **GPS-degraded feedback.** `LocationTracker` used to silently drop points
  with `horizontalAccuracy >= 50` (or invalid) while recording. New
  `isGPSDegraded` flag (set per received fix, reset on `start()`) drives a
  small warning-colored "GPS signal weak" note under Record's stat row —
  recording behavior unchanged, no fabricated points.
- **Pause is now visually distinct.** Pausing keeps the existing card/layout
  but the header sport icon drops to `.secondary` (bounce stops) and a red
  `PAUSED` capsule appears next to it.

## `(pending)` — HealthKit write (optional workout export)

- **New `Core/Health/HealthKitService.swift`.** Single flat `enum` (matches
  `BackupService`/`GPXParser` shape) with availability check, share-auth
  request, and `saveWorkout(from:)`. Writes an `HKWorkout` (sport mapped via
  `HKWorkoutActivityType(sport:)`, duration, GPS distance) and attaches the
  route polyline via `HKWorkoutRouteBuilder.insertRouteData` +
  `finishRoute(with:)`. Route samples re-report accuracy at the recorder's
  accepted 50m ceiling (honest — never overstated). Active energy not written:
  Larping's calorie figure is a crude formula, not measured data.
- **Project config.** `com.apple.HealthKit` in target `SystemCapabilities`,
  new `larping/larping.entitlements` (`com.apple.developer.healthkit`,
  referenced by `CODE_SIGN_ENTITLEMENTS`, added to the synced-group
  `membershipExceptions` like `Info.plist`), and
  `INFOPLIST_KEY_NSHealthShare/UpdateUsageDescription` build settings for
  scalar-key security copy. `import HealthKit` auto-links; no pbxproj
  framework phase needed.
- **Profile "Health" section** (shown only when
  `HKHealthStore.isHealthDataAvailable()`) with an opt-in
  "Allow HealthKit access" button; reflecting on re-appear.
- **Record Finish hook.** The local SwiftData save happens first and
  unconditionally; only after it succeeds does a fire-and-forget
  `Task { await HealthKitService.saveWorkout(from: activity) }` mirror the
  workout. HealthKit denial/absence/failure never blocks or loses a
  recording.
- No data-model schema change (no stored active-energy field — not needed for
  an energy-less write).

## `(pending)` — HealthKit read / import (Watch workouts into Larping)

- **`HealthKitService` read side.** `fetchRecentWorkouts(limit:)`,
  `fetchRoute(for:)` (HKSampleQuery for `HKWorkoutRoute` + `HKWorkoutRouteQuery`,
  continuation-based), `heartRateSamples(for:)` (windowed HKSampleQuery,
  gated on read auth). `requestAuthorization` now also requests read for
  workouts/routes/heart-rate. `SportType(workoutActivityType:)` back-maps
  Apple's activity types (unknown types → `.other`).
- **`ImportHealthKitView`** mirrors `ImportGPXView`: newest workouts list,
  sport-type override picker, summary, single Import action. Route polyline →
  track points (`source: "healthkit_import"`), heart rate merged onto the
  nearest point at-or-before its timestamp (`heartRateBpm` finally populated
  for Watch-recorded activities); distance prefers `HKWorkout.totalDistance`
  else route sum; elevation/max speed from route. No route/HR → imports
  metadata-only. Graceful paths: unavailable (menu entry hidden), denied
  (explanation + Open Settings), empty store (`ContentUnavailableView`).
- **Activities toolbar** became an Import `Menu` (GPX + HealthKit) — GPX
  import itself unchanged.
- Import goes through the existing `ActivitiesStore.create` path, so backups,
  rename, share, stats all work identically.

## `(pending)` — Heart-rate display, backup timestamp, GPX sport autodetect

- **Heart-rate stats finally visible.** Imported HealthKit activities carry
  HR samples but nothing displayed them. `CDActivity` gains `@Transient`
  `maxHeartRateBpm`/`averageHeartRateBpm` (derived from track points);
  `ActivityDetailView` shows Avg HR / Max HR stat tiles when present; Stats
  adds per-sport "max N bpm" and a "Highest heart rate" personal best. Live
  iPhone recordings still have no HR — tiles just stay hidden (nil).
- **Last-backup timestamp.** Profile stamps `@AppStorage("lastBackupDate")`
  on every successful export and import and shows "Last backup: …" in the
  Backup section — a cheap answer to "when did I last back up?".
- **GPX sport auto-detect.** `GPXParser` captures the `<type>` element;
  `sportType(from:)` maps it (case-insensitive substring: run/cycl/rid/bike/
  walk/hik/trail/swim; unknown → nil). `ImportGPXView` pre-selects the
  detected sport when parsing a file, overriding the `.run` default.
  Substring order matters: "trail run" counts as Run (run checked before
  trail), "Cycling_Sport"→Ride. Covered by two new `GPXParserTests`.

## `(pending)` — Splash screen + immersive Record tab

- **Animated splash.** `SplashView` (Features/Root) overlays the app on
  launch: `LogoHorizontal` wordmark over `Color.canvas`, tinted white in dark
  mode / black in light mode via `colorScheme` (the template asset recolors —
  no new PNGs). `larpingApp` fades it out after ~1.4s. The static launch
  screen previously flashed system white/black ahead of the app; the explicit
  `Info.plist` now sets `UILaunchScreen` with `UIColorName = Canvas` so the
  pre-SwiftUI phase matches the splash in both modes — seamless handoff.
- **Record's dark overlay moved from top nav to bottom tab bar.** The old
  `toolbarBackground(Color.black.opacity(0.75), for: .navigationBar)` +
  dark scheme made the Record nav bar a black strip over the map. Removed —
  the top is now transparent full-bleed (no title, recenter button remains
  top-trailing). The same black overlay is re-applied to the bottom **tab
  bar**, scoped with `.toolbarBackground(…, for: .tabBar)` from Record's own
  view, so in dark mode the map + bottom control card + tab bar read as one
  dark block. Other tabs keep the default liquid-glass tab bar untouched.
  Light mode unchanged (automatic).

## `(pending)` — Active duration fix (pause no longer inflates duration/pace)

Root cause: `LocationTracker.stop()` stored `endedAt - startedAt` (wall clock),
so pausing inflated `durationSeconds`, average pace, and average speed.
The on-screen timer was already pause-aware, but as a separate `@State`
`elapsedSeconds` in `RecordView` — two clocks, one right and one wrong.

Fix keeps active-duration state in the session logic (`LocationTracker`), not
the UI:
- `LocationTracker` now owns the clock: `activeTime` (sub-second-precise
  `TimeInterval`) accumulated per recording interval at start/pause/resume/
  finish boundaries, plus `elapsedSeconds` (whole-second view) driving the
  on-screen timer via its own 1s tick. `startedAt`/`endedAt` remain real
  wall-clock timestamps.
- `Recording` gains `activeDurationSeconds` + `durationSeconds` (Int).
  `RecordView`'s own timer is gone — the tracker is the single source of
  truth for both display and persistence.
- `durationSeconds` stored = `activeTime` floored; `averageSpeedMps` divides
  distance by `activeDurationSeconds` (guarded `> 0.5s` for near-zero
  recordings). Distance, elevation, calories unchanged; GPX/HealthKit import
  paths untouched (GPX has no pause concept; HealthKit uses Apple's own
  active duration).
- Injectable `currentDate` clock seam (default `Date()`) lets tests drive
  start/pause/resume/finish deterministically — no real sleeps.

New `LocationTrackerTests` (fake clock, `@MainActor`): no pause, single
pause (the 10'/20'/10' example → active 20'), multiple pause/resume
accumulation, finish-while-paused, finish-while-recording, near-zero
duration safety, and `elapsedSeconds` tracking.

## `(pending)` — CI: UI test "operation never finished bootstrapping" crash

GitHub Actions UI test run died with `Early unexpected exit, operation never
finished bootstrapping` before the test runner connected. Root cause: the Test
step let `xcodebuild test` boot the simulator lazily and launch the runner
before CoreSimulator was fully ready (a known flake on `macos-latest` fresh
VMs). Fix in `.github/workflows/ci.yml`: a `Prepare Simulator` step that
`simctl shutdown all`, boots the target device, then `simctl bootstatus -b`
(blocks until boot completes) before running tests. Note that dropping the
proposed `erase all` step is by design — each GitHub Actions job runs on a
pristine VM, so there are no stale devices to erase; hardcoded
`SimDeviceType`/`SimRuntime` ids are the real flake risk (they differ per
Xcode image) and were left out.

## Tech-debt pass: backup/save correctness, stats cap, store tests

Four silent-failure / correctness issues fixed in one pass:

- **Backup export capped at 2000 + `try?` swallowed errors.** `BackupService
  .backupFile` silently fetched at most 2000 activities (the "Export all"
  button was a lie past 2000) and silently fell back to an empty list on any
  SwiftData fetch failure — the user would see "backup exported" with zero
  data in it, the only off-device copy of their activities. Removed the
  fetch limit entirely and changed to `try` so errors propagate to the
  Profile export UI instead of masquerading as success.
- **Backup re-import duplicate-on-failure bug.** `restore` built the
  idempotency set of existing activity IDs with `(try? ...)?.map(...)` — if
  the SwiftData fetch failed, the set was treated as empty, causing every
  activity in the backup to be re-imported as duplicates. Changed to `try`
  so a failure aborts the import and surfaces the error to the user instead
  of silently duplicating every record.
- **Auto-save-on-finish swallowed SwiftData save errors.** `ActivitiesStore
  .create` called `try? modelContext.save()`. On a save failure (disk full,
  corrupt store, migration gone wrong) the activity was inserted into the
  in-memory `activities` array and a "saved" alert shown — but the data
  never persisted, so it vanished on next launch; meanwhile a HealthKit
  workout was still written for the phantom activity. `create` now `throws`;
  only the in-memory insert runs after a confirmed save. All three callers
  (Record finish, GPX import, HealthKit import) wrap the call in `do/catch`
  and surface errors to the user instead of silently reporting success.
- **Stats "All time" silently capped at 500 activities.** `ActivitiesStore
  .refresh()` capped `activities` at 500 for the Record heatmap, but
  `StatsView` uses the same array for all-time totals and personal-best
  computations — silently wrong past 500 activities. Removed the cap from
  the store; the heatmap now slices `activities.prefix(500)` itself, leaving
  Stats to see the full dataset.
- **ActivitiesStoreTests added** covering create-persists, rename, delete,
  and the all-time-uncapped refresh behavior. Saved the heatmap
  `DateFormatter` as a static let in `ActivitiesListView` to avoid
  re-creating it on every body evaluation. Fixed a stale doc comment in
  `HealthKitService` that claimed the read/import side "is deliberately not
  here yet" — it's been there since the HealthKit import pass.

## Tech-debt pass 2: persistence error propagation

Second persistence-correctness pass, extending the first (`create` throws) to
every user-visible persistent op. Principle: **a persistence failure must
never present as a successful mutation**, and an uncommitted (pending) state
must never survive a failed save to be committed later by an unrelated one.

- **`ActivitiesStore.rename`/`delete` no longer swallow save failures.** Both
  used `try? modelContext.save()` — renaming the event in memory / removing
  it from `activities` even when the save failed, so the UI showed a success
  that reverted on next launch. Both now `throws`: rename reverts the
  in-memory name on failure; delete rolls the pending delete back out of the
  context. `ActivityDetailView` surfaces both ("Couldn't save changes" alert)
  and no longer dismisses on a failed delete.
- **`create` now rolls back uncommitted inserts on save failure.** The first
  pass made `create` throw, but a failed save left the new activity *pending
  in the context* — absent from `store.activities`, yet visible in the
  `@Query` list and committed by any later unrelated save. `create` now
  `modelContext.rollback()`s on failure, leaving zero trace.
- **`BackupService.restore` is atomic / all-or-nothing.** A save failure
  previously left every inserted backup activity pending in the context: the
  error surfaced (pass 1) but the partial import stuck around and could be
  committed by a later save. Restore now `rollback()`s the whole uncommitted
  import — the store is left exactly as it was, so re-importing after fixing
  the cause is clean. Also guards against malformed backups listing the same
  activity id twice (only the first occurrence imports, the rest count as
  skipped).
- **Last user-visible persistence `try?` removed.** `RecordView
  .suggestedEventName` replaced a raw `modelContext.fetch` (`try?` → empty on
  failure → could suggest an already-used name) with the already-loaded
  `activitiesStore.activities`.
- **Track-point "duplication on reimport" investigated → not a bug.**
  Idempotency keys on **activity** ids and delete cascades free an activity's
  point ids, so re-importing a backup after deleting an imported activity
  revives it (activity + points) exactly once — never as duplicates. The only
  path that regenerates ids (`create`, for live/GPX/HealthKit import) is off
  the restore path entirely. See `docs/KNOWN_ISSUES.md`.
- **Test seams, not a DI framework.** `ActivitiesStore.persistOperation`
  (nil → real save) and the defaulted `BackupService.restore(persist:)`
  parameter (default → real save) let tests force a save failure with a plain
  in-memory container.
- **Tests added.** ActivitiesStoreTests: create-rollback leaves zero rows in
  a fresh `ModelContext`; failed rename keeps the stored name in memory +
  persisted; failed delete keeps the activity alive in memory + store.
  BackupServiceTests: re-import twice duplicates neither activities nor track
  points; duplicate ids within one file import once; restore save-failure
  leaves no partial import; delete-then-reimport restores cleanly. All
  failure assertions read back through a **fresh** `ModelContext` so they
  prove store state, not just the object's in-memory copy.

## Next / not built

Deferred / do-not-build items, so a fresh session doesn't re-propose them:

- **Live-record notification** (Dynamic Island / Lock Screen with
  Pause/Finish actions) — needs ActivityKit **Widget Extension target**
  (UI cannot be defined from the main app); deferred. Adding it requires a new
  Xcode target, best added via Xcode GUI (File → New Target → Widget
  Extension) or careful pbxproj surgery.
- **Scheduled/automatic backup** — background app refresh + notification +
  file-conflict resolution; current manual export/import is sufficient.
- **Restore duplicate-conflict resolution** beyond skip — edge case for
  multi-device power users; "skip existing" is safe and correct.
- **Apple Watch companion app** — separate watchOS codebase/product decision;
  out of scope by design (this is an iPhone recorder).
- **Cloud sync / iCloud entitlement** — needs paid Apple Developer Program;
  changes the fundamental architecture. Backup via iCloud Drive suffices.
- **Social features** (feeds/followers) — contrary to "private by
  construction".
- **Workout auto-detection** — significant ML/HealthKit complexity; manual
  Start is clear UX.
- **Custom/user-defined sports** — model migration + share-template changes;
  the current 6 sports cover real use.
- **Step cadence display** — Watch exposes steps/min, not RPM; the field stays
  `cadenceRpm` and unpopulated for now (see `KNOWN_ISSUES.md`).
- **Resting HR / VO2 max** — needs `HKQuantityType` reads + personal-best
  enrichment; nice-to-have, low impact.
- **HealthKit active energy / calories** — energy deliberately not written to
  Health (crude local formula); a stored `activeEnergyKiloJoules` field and
  real energy imports would be needed for accuracy.