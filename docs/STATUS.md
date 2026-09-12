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

## Next / not built

- **Live-record notification** (Dynamic Island / Lock Screen with
  Pause/Finish actions) — needs an ActivityKit **Widget Extension target**
  (UI cannot be defined from the main app); deferred. Adding it requires a new
  Xcode target, best added via Xcode GUI (File → New Target → Widget
  Extension) or careful pbxproj surgery.
- Scheduled/automatic backup.
- Restore duplicate-conflict resolution beyond skip.