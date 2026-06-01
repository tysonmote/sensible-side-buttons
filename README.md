<img src="icon.png" width="150" alt="SensibleSideButtons icon" />

macOS mostly ignores the M4/M5 mouse buttons commonly used for navigation. Third-party apps can bind them to ⌘+[ and ⌘+], but that only works in a small number of apps. With this tool, your side buttons simulate three-finger swipes so you can navigate almost any window with a history.

Upstream project: [archagon/sensible-side-buttons](https://github.com/archagon/sensible-side-buttons)  
More background: [sensible-side-buttons.archagon.net](https://sensible-side-buttons.archagon.net)

This fork adds **native Apple Silicon (arm64) builds**, modern macOS permissions handling, and reliability fixes while keeping the original Objective-C implementation.

## Requirements

- macOS 12 Monterey or later
- Xcode 15+ (full Xcode.app, not Command Line Tools only)
- A mouse with side buttons (typically buttons 4 and 5)

## Build (Apple Silicon and Intel)

1. Open `SwipeSimulator.xcodeproj` in Xcode.
2. Optional: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your `DEVELOPMENT_TEAM` for signing.
3. Select the **SensibleSideButtons** scheme, then **Product → Build** (or Archive for release).
4. The product is `SensibleSideButtons.app` (universal `arm64` + `x86_64` by default).

From the command line:

```bash
xcodebuild -project SwipeSimulator.xcodeproj \
  -scheme SensibleSideButtons \
  -configuration Release \
  CODE_SIGN_IDENTITY=- \
  build
```

Verify architectures:

```bash
file build/Release/SensibleSideButtons.app/Contents/MacOS/SensibleSideButtons
# expect: Mach-O universal binary with arm64 and x86_64
```

## Permissions

On first launch, enable **both**:

1. **Privacy & Security → Input Monitoring** — required to listen for side-button events (`CGPreflightListenEventAccess`).
2. **Privacy & Security → Accessibility** — required to post synthetic swipe gestures.

Use the menu item **Open Accessibility Settings**, then add `SensibleSideButtons` to both lists. Toggle **Enabled** off and on after granting access.

## Login at startup

- **macOS 13+**: use the menu bar item **Launch at Login** (uses `SMAppService`).
- Older approach: **System Settings → General → Login Items** and add `SensibleSideButtons.app`.

## Debug tools

The project includes `swipesiml` and `swipesimr` command-line targets that post a single synthetic left or right swipe (useful when testing gesture synthesis).

## Distribution

See [docs/RELEASE.md](docs/RELEASE.md) for Developer ID signing, notarization, and DMG packaging.

## License

GPL-2.0 — see [LICENSE](LICENSE). Original copyright Alexei Baboulevitch (2018).
