# Status (work in progress)

Saved 2026-11-12 (UTC).

Written (all code is on main)
- PLAN.md, README.md, DECISIONS.md (UI decisions still live in App/UI_NOTES.md and need merging in)
- Packages/LedgerlyCore: complete, 374 unit tests pass on Linux (Swift 5.10); compiles in Swift 6 mode on GitHub Actions (Xcode 16.4)
- App/Data, App/Services, App/Intents, App/ViewModels, App/Views, UITests, project.yml, scripts/verify.sh
- .github/workflows/ci.yml: builds and tests on a cloud Mac (macos-15 runner)

Not verified yet
- The full app (screens, App Intent, onboarding, CSV, UI tests) has never been compiled. Expect compile errors in the first Actions runs.
- No feature has been run in a simulator. No screenshots yet.

Next
1. Read the Actions build log for main, fix compile errors, repeat until build + all tests are green with zero warnings
2. Merge App/UI_NOTES.md into DECISIONS.md
3. Independent review against SPEC.md, fix findings, re-test
4. Look at the UI-test screenshots (light and dark) from the ledgerly-ci artifact
5. Decide the iPhone install route (paid developer account + TestFlight, or free sideloading) and add a workflow for it
