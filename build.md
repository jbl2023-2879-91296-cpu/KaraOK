# Building KaraOK for Android

Run these commands in PowerShell from the repository root. Install Flutter,
Android SDK/platform tools, and Java 17; resolve Android issues reported by
`flutter doctor -v` and accept SDK licenses with `flutter doctor --android-licenses`.

## Signing setup

Release builds require a private keystore and fail if signing is unconfigured.
There is no debug-key fallback. Create local signing configuration interactively:

```powershell
./tools/build_karaok.ps1 -SetupSigningOnly
```

The build accepts `frontend/android/key.properties` or the process environment
variables `KARAOK_KEYSTORE_PATH`, `KARAOK_KEY_ALIAS`, `KARAOK_STORE_PASSWORD`, and
`KARAOK_KEY_PASSWORD`. Keep the keystore and passwords outside source control and
back up the signing identity securely; app updates require the same identity.

## Build and package

```powershell
./tools/build_karaok.ps1 -PlanOnly -NonInteractive
./tools/build_karaok.ps1 -NonInteractive
# Play Console bundle:
./tools/build_karaok.ps1 -Format aab -NonInteractive
```

The default mode is `release`. The script restores dependencies, runs Flutter
analysis and tests, builds, and copies versioned artifacts to
`dist/KaraOK-v<version>+<build>-<mode>-android/`. A timestamp distinguishes repeat
builds. `build-manifest.json` records artifact hashes and the effective API URL.
The original artifacts remain in `frontend/build/app/outputs/`.

Set versions in `frontend/pubspec.yaml` or pass `-VersionName 1.1.0 -BuildNumber 2`.
Use `-SplitPerAbi` for separate APK architectures, `-Clean` for a clean build,
and `-OutputDirectory` to change packaging location. `-SkipChecks` bypasses the
Flutter verification and should not be used for release validation.

## API selection

Precedence is `-ApiBaseUrl` (alias `-AppBaseUrl`), then process environment
`KARAOK_API_BASE_URL`, then mode default:

| Mode | Default |
| --- | --- |
| Release/profile | `https://139.99.89.112/api` |
| Debug | `http://10.0.2.2:5000/api` (Android emulator) |

All endpoints must end in `/api`; release/profile endpoints require remote HTTPS.
The script passes Flutter's `API_BASE_URL` define. Do not supply API URL keys
through `-DartDefine`. Direct `flutter build` commands must supply
`--dart-define=API_BASE_URL=<url>` explicitly.

## Local device builds

Start the backend separately. For the Android emulator:

```powershell
./tools/build_karaok.ps1 -Mode debug -NonInteractive
adb install -r frontend/build/app/outputs/flutter-apk/app-debug.apk
```

For a USB-connected phone with debugging enabled:

```powershell
adb reverse tcp:5000 tcp:5000
./tools/build_karaok.ps1 -Mode debug -ApiBaseUrl http://127.0.0.1:5000/api -NonInteractive
adb install -r frontend/build/app/outputs/flutter-apk/app-debug.apk
```

Keep the USB connection and reverse mapping active for the local API.
See [tools](tools/README.md) for full repository checks and [deployment](deploy.md)
for backend release and health verification.
