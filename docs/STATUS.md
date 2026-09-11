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

## Next / not built

- **Live-record notification** (Dynamic Island / Lock Screen with
  Pause/Finish actions) — needs an ActivityKit **Widget Extension target**
  (UI cannot be defined from the main app); deferred. Adding it requires a new
  Xcode target, best added via Xcode GUI (File → New Target → Widget
  Extension) or careful pbxproj surgery.
- Scheduled/automatic backup.
- Restore duplicate-conflict resolution beyond skip.