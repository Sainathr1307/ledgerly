<!-- Notes from the scaffold/data-layer work, for whoever writes README.md. Not shipped in the app. -->

- **No app icon is included.** `App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` declares the single 1024×1024 iOS slot with no image, so the build succeeds and the app shows the blank placeholder icon. To add one, drop a 1024×1024 PNG into that folder and add `"filename" : "YourIcon.png"` to the image entry.
- `App/Resources/Info.plist` is written by XcodeGen from `info.properties` in `project.yml` each time `xcodegen generate` runs. Change the properties in `project.yml`, not the plist.
- Signing: `DEVELOPMENT_TEAM` is blank and the bundle id is `com.example.ledgerly` (both in `project.yml`). Simulator builds work as is; a device build needs both set.
- FinanceKit is compiled out. The two commented blocks in `project.yml` (the `entitlements:` block and `SWIFT_ACTIVE_COMPILATION_CONDITIONS`) turn it on once the entitlement exists.
- `scripts/verify.sh` needs Xcode 16+ and XcodeGen (`brew install xcodegen`). It picks the first iPhone simulator on iOS 18 or later, or the one in `SIM_UDID`.
