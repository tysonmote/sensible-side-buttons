# Releasing SensibleSideButtons

## Local release build

1. Open `SwipeSimulator.xcodeproj` in Xcode.
2. Set **Signing & Capabilities** to your **Developer ID Application** certificate (not "Apple Development") for distribution outside your Mac.
3. **Product → Archive** the **SensibleSideButtons** scheme.
4. **Distribute App → Developer ID** and export `SensibleSideButtons.app`.

Confirm universal binary:

```bash
lipo -archs /path/to/SensibleSideButtons.app/Contents/MacOS/SensibleSideButtons
```

## Notarization

Apple requires notarization for apps downloaded outside the Mac App Store.

```bash
APP=/path/to/SensibleSideButtons.app
ZIP=SensibleSideButtons.zip

ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

xcrun stapler staple "$APP"
```

Validate:

```bash
spctl -a -vv "$APP"
codesign -dvvv "$APP"
```

## DMG (optional)

1. Create a read/write disk image folder containing `SensibleSideButtons.app` and an **Applications** symlink.
2. Convert to compressed read-only DMG with **Disk Utility** or `hdiutil`.

## Version numbers

Update `CFBundleShortVersionString` and `CFBundleVersion` in `SideButtonFixer/Info.plist` before each release.

## Hardened Runtime

Release builds enable **Hardened Runtime** in the Xcode target. If notarization fails, check entitlements in `SideButtonFixer/SideButtonFixer.entitlements` and add only what you need.
