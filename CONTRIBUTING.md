# Contributing to Larping

Thanks for looking at this. It's a small, single-purpose iOS app — keep
changes small and in the same spirit: offline-first, no third-party deps, no
networking.

## Before you start

Read these two first, in order — they cover the whole app without you having
to scan the source tree:

1. `docs/ARCHITECTURE.md` — current structure, theming, conventions.
2. `docs/KNOWN_ISSUES.md` — things that look like bugs but aren't, plus real
   open gaps (check here before re-diagnosing something).

`docs/STATUS.md` has the commit-by-commit history/reasoning if you want the
"why" behind a non-obvious decision.

## Setup

- Xcode 26+ (project uses `IPHONEOS_DEPLOYMENT_TARGET = 26.5`).
- Open `larping.xcodeproj` — no package manager, no `pod install`, no
  `.xcworkspace`. Files dropped into `larping/` join the build automatically
  (synchronized file system group); no project-file edits needed for new
  Swift files.
- No secrets, no `.env`, no backend to run — the app is 100% on-device.
- The project has the maintainer's `DEVELOPMENT_TEAM` committed in
  `project.pbxproj` for device-signing convenience. Simulator builds (see
  below) don't need signing and work as-is. To run on a physical device,
  change the Team in Xcode → Signing & Capabilities to your own — don't
  commit that change.

## Build & verify

```bash
xcodebuild -project larping.xcodeproj -scheme larping \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build \
  2>&1 | grep -Ei "error:|warning:|BUILD FAILED|BUILD SUCCEEDED"
```

Two warnings always appear and are expected (not yours to fix): the
`AccentColor` asset-symbol redeclaration, and the `appintentsmetadataprocessor`
"no AppIntents.framework" note.

`larpingTests` has unit coverage for the non-trivial logic (GPX parsing,
formatters, backup round-trip, share image compose). Run it via Xcode's Test
navigator or `xcodebuild ... test` (swap `build` for `test` in the command
above, add a `-destination` with a device name e.g. `platform=iOS
Simulator,name=iPhone 17`). If you add non-trivial logic (a branch, a
parser, a calculation), leave a small `XCTestCase` behind for it.

## Conventions

- No third-party dependencies. stdlib/SwiftUI/UIKit/MapKit/CoreLocation/
  PhotosUI only — don't add a package for something a few lines can do.
- SwiftData + `@Observable`, main-actor-by-default (see
  `docs/ARCHITECTURE.md` → Conventions).
- Black/white monochrome theme via `Assets.xcassets` color sets
  (`Color.ink`, `.canvas`, etc.) — no hardcoded colors in views.
- Match existing file placement: `Core/` for models/services, `Features/<X>/`
  for screens.

## Updating docs

If your change alters what a doc describes (a feature, a file, a data model
field, a known gap), update that doc **in the same PR** — see "Keeping docs
in sync" in `CLAUDE.md`. A PR that changes behavior without touching docs
will get asked to add it.

## Pull requests

- Keep PRs scoped to one change. Explain the *why* in the description if it's
  not obvious from the diff.
- Run the build command above before opening the PR.
- No formatting-only PRs that touch unrelated files.
