# iOS App — Known Issues / Non-issues

Things that look like bugs but aren't, plus real open gaps. Check here before
re-diagnosing from scratch.

## "Elevation gain always shows 0 / missing" — not a bug

`ActivityDetailView` and the record screen hide the elevation stat when
`elevationGainMeters <= 0`. On the iOS Simulator, a manually-set "Custom
Location" provides no altitude (`location.verticalAccuracy < 0`), so the
recorder never accumulates elevation — the stat is correctly hidden because
it's genuinely zero. Confirm on a real device, or via GPX import (GPX
elevation parses and threads through correctly).

## Simulator-only location debugging

Debug > Location > Custom Location in the simulator only sets a fixed point
(no movement, no altitude, no speed). Use a GPX-based simulated route in
Xcode's scheme location settings for realistic recording tests.

## Sample data only appears on a fresh install

The one-time seed (`SeedData`, flag `seedSampleDataV1`) fires only when the
database is empty AND the flag is unset. If you installed a build before the
seed existed (or an older build), **uninstall the app** once to see the sample
activities — deleting everything yourself never brings them back (by design).

## SwiftData schema changes = uninstall to reinstall

The store schema changed several times during development. Adding a new
**optional** model property (like `CDActivity.eventName`) is a lightweight
migration SwiftData applies automatically on launch and normally needs no
reinstall. But a failing/missing auto-migration still reads as a crash on
launch. When testing across schema-affecting changes: uninstall first, or
`rm -rf ~/Library/Developer/Xcode/DerivedData/larping-*` and reinstall.

## Route map in detail needs a network

The map panels (activity detail + record) use Apple Maps, which needs a
network connection to render tiles. The **recorded data (activities, points,
stats) is always local and works offline**; only map imagery needs
connectivity. Offline the polyline renders over an empty gray basemap — data
is fine.

## No true background iCloud sync (paid entitlement)

The app is fully offline and stores everything in SwiftData; it does NOT
auto-sync across devices. True CloudKit sync needs the iCloud capability —
**Apple Developer Program membership ($99/y)** + a container in signing
entitlements — not just code.

**What works today:** Profile → "Export all activities" (system file picker) →
save into **iCloud Drive** or Files; **Import backup** brings it back.

## Backup/restore is manual, not scheduled

Export/import both exist and restore is idempotent (skips existing ids, never
duplicates/deletes, rejects junk). Missing: scheduled/automatic backup, plus a
migration story for `BackupContainer.version` if the schema ever changes.

## Live-record notification is NOT built

No Dynamic Island / Lock Screen activity during recording, and no
Pause/Finish actions from a notification. ActivityKit Live Activities require
a **Widget Extension target** to define the presentation UI — the main app
can only start/update/end an activity. Adding it = a new Xcode target (not
just Swift files). Deferred by design; see `docs/STATUS.md` "Next".

## "Double location button on Record map" — gone

A default `MapUserLocationButton` was duplicating the custom toolbar button;
the default one was removed. Re-add the default (`mapControls`) and you'll
see the double again.

## Share: plain classic card is a transparent PNG; map cards are opaque

The classic template with **no photo** exports a transparent-background PNG
(white content with dark shadows) so it can be pasted on any backdrop. With a
photo, the card is photo + black dim, fully opaque. The map template + video
have their own opaque map background. So "the share image is always space
dark" is no longer true — only the map fallback (no network tiles) and the
photo-less classic video-era path use `spaceBlack`. Not a bug.

The **preview thumbnail** for that transparent card sits on a black backing
in `ShareActivityView` (`classicPreview`) purely so the white content is
visible in light mode — that backing is UI chrome only, not part of the
composed image. If the exported/shared/saved file ever looks like it has a
black background, that's a real regression (check `ShareImageComposer.compose`
still leaves the canvas untouched when `photo == nil`); the on-screen preview
having one is expected.

## Bundling fonts via the synchronized group silently fails

Xcode's `PBXFileSystemSynchronizedRootGroup` does **not** copy `.ttf` files
into the app bundle (hit with Domine). A future custom font would need either
a real `Copy Bundle Resources` entry plus an exception, or in-memory embed.
Don't drop a font into `larping/` and assume it ships.

## Apple Maps attribution/logo cannot be hidden

MapKit's terms of service require the Apple logo and legal attribution
overlay to remain visible on any map view — there's no public, compliant API
to remove or hide it. Clipping/cropping it out would violate Apple's usage
terms and risks App Store rejection, so Record and Activity Detail's map
views intentionally leave it as-is. Not a bug, not fixable within the rules.

## Prominent-button text contrast is hand-managed

`.borderedProminent` labels on the accent color need a `colorScheme`-based
foreground (white in light mode on `#463CFF`, black in dark mode on lime) —
Start, Share. Destructive buttons are red+white natively and must NOT get
that override. Keep this in mind when adding buttons.

## Heart-rate / cadence fields: live recordings stay nil

`CDTrackPoint.heartRateBpm` / `cadenceRpm` are optional. Live recordings run
on iPhone GPS only, so they stay `nil` for everything recorded in-app. They
get populated only via **HealthKit import**: heart-rate samples are matched to
the imported workout's track points (nearest HR sample at-or-before each
point's timestamp). Cadence (`cadenceRpm`) remains always-nil — Apple Watch
exposes *step cadence*, not RPM, and we deliberately don't rename the field or
map it. Display code hides heart-rate UI when nil — an invisible gap, not a
bug.

## HealthKit write is best-effort and silent

`HealthKitService.saveWorkout(from:)` guards on availability + authorization
and swallows errors — a failed/denied write never surfaces UI and never
blocks the local save. It also uses the iOS-17-deprecated
`HKWorkout(activityType:start:end:...)` initializer by design (the
`HKWorkoutBuilder` replacement targets live workout session collection,
overkill for a post-hoc mirror); expect the deprecation warning in builds.
The route's reported accuracy is re-claimed at the 50m ceiling the recorder
accepted, so HealthKit consumers never see accuracy better than what was
guaranteed.