# Status (work in progress)

Saved 2026-11-12 (UTC) because the usage limit was about to run out.

Done
- PLAN.md
- Packages/LedgerlyCore: complete, 374 unit tests pass on Linux (Swift 5.10); compiles in Swift 6 mode on GitHub Actions (Xcode 16.4)
- App/Data, App/Services (notifications, lock), project.yml, scripts/verify.sh
- CI workflow lives on branch `ci/smoke` (.github/workflows/ci.yml); not on main yet so half-finished code doesn't trigger failing builds

In progress (files may be partial)
- UI agent: App/LedgerlyApp.swift, App/ViewModels, App/Views, UITests
- Platform agent: App/Intents, onboarding + Wallet guide, WalletTransactionLogger, DemoDataSeeder, FinanceKit, CSV import/export, README.md, DECISIONS.md

Next
1. Let both agents finish (resume them if they were cut off)
2. Add .github/workflows/ci.yml to main, push, fix compile errors from the Actions log until build + tests are green
3. Second smoke run on ci/smoke failed in the build step; cause not read yet
4. Independent review against SPEC.md, fix, re-test
5. Decide iPhone install route (TestFlight via paid developer account, or free sideloading)
