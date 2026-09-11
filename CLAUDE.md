# Larping — repo guide

SwiftUI iOS app, brand "Larping", tagline "actually works". Like Strava, but
just the recording — and private by construction: **fully offline, on-device
SwiftData storage, zero networking, no server, no account.**
Black/white minimalist theme (`Ink`/`Canvas`/`Accent` etc, see
`docs/ARCHITECTURE.md`).

**Start here, not the source tree**: `docs/` is written so a new session can
get fully oriented without re-scanning source. Read these before doing
anything else:

| File | Covers |
|---|---|
| `docs/ARCHITECTURE.md` | App structure, conventions, theming, Info.plist gotchas |
| `docs/STATUS.md` | Build history, commit by commit, with root-caused bugs |
| `docs/KNOWN_ISSUES.md` | Things that look like bugs but aren't, plus real open gaps |
| `README.md` | Features, data model, build & verify |

Only fall back to reading source directly for the specific file you're about
to change — not to rebuild context the docs above already have.

## Repo layout

This is the root of the git repo — `larping.xcodeproj` is at top level, next
to its source (`larping/`), tests (`larpingTests/`, `larpingUITests/`), and
`docs/`.

`archive/` holds a prior, now-removed NestJS backend and its docs, kept for
historical reference only. It is not part of the current app (which has zero
networking) and shouldn't be read for context on how the app works today.

## Verification

```bash
xcodebuild -project larping.xcodeproj -scheme larping \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build \
  2>&1 | grep -Ei "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```
