# KaraOK app (Flutter)

The KaraOK mobile app records or selects karaoke playback, sends it to the
KaraOK API for analysis, and shows the score, five sound measurements, noise
and distortion estimates, and waveform and spectrogram reports. Android is the
shipped target; web and desktop builds are used for development and testing.

## What the app does

- Opens straight into guest mode unless a saved login can be restored.
- Guests get three successful audio evaluations per device. Their reports stay
  on the device and are never moved into an account.
- Home, Records and Settings are the three bottom-navigation tabs.
- **Evaluate Audio Quality**: record up to five minutes or pick a file, then
  see the score, the five measurements and the visual report.
- **Generate Audio Settings Suggestion**: enter the amplifier's scale and
  current knob positions, record, and get five suggested positions with
  explanations and a Record Again to Verify step. Listener feedback (Better,
  Same, Worse) is saved with the suggestion.
- Records: search, status chips, date and score filters, newest/oldest sort,
  and side-by-side comparison of two reports.
- Three illustrative sample assessments appear until the first real one.
- Glossary of terms is reachable from Settings and from every report.
- Sign-up needs only email and password. Profile details are added later from
  Settings, with a single reminder on Home.
- Passwords are 8 to 128 characters with uppercase, lowercase, number and
  symbol. Only the last successful email is remembered, never the password.

## Requirements

- Flutter SDK compatible with Dart `^3.12.2`
- Android API 24 or newer
- A running KaraOK API (see the [backend guide](../backend/README.md))

## Run

```powershell
cd frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5000/api
```

| Target | `API_BASE_URL` |
| --- | --- |
| Windows or Flutter web | `http://127.0.0.1:5000/api` |
| Android emulator | `http://10.0.2.2:5000/api` |
| Physical phone on your network | `http://<computer-LAN-IP>:5000/api` |
| Production | `https://139.99.89.112/api` |

`./tools/run-dev.ps1` from the repository root starts the backend, Admin
Console and app together.

## Code layout

```text
lib/
|-- app/                 Theme tokens, app shell, routes
|-- core/                Environment, networking, media, sessions, storage
|-- features/
|   |-- account/         Settings and profile
|   |-- assessments/     Recording, file selection, upload
|   |-- auth/            Sign-up, OTP, login, recovery, startup
|   |-- home/            Home tab
|   |-- reports/         Results, Records, comparison, glossary
|   `-- sound_settings/  Amplifier setup and settings suggestions
`-- shared/widgets/      Shared UI: page scaffold, buttons, banners, states
```

## UI conventions

Use the shared pieces instead of one-off styling, so screens stay consistent:

- Colors, spacing (`AppSpacing.page` is the 20 px page gutter), radii and type
  live in `lib/app/app_theme.dart`. Avoid raw font sizes and hex colors.
- Pages with a form or simple content use `AppPageScaffold`. App-bar titles are
  plain `Text` and inherit the theme style; do not center or recolor them.
- `AppSectionHeader` puts an optional action (for example **View all**) on the
  heading row.
- `AppPrimaryButton` / `AppSecondaryButton` for main actions, `AppPromptLink`
  for "Don't have an account? Sign Up" rows, `AppEmptyState` and
  `AppErrorState` for empty and failed loads.
- Text fields inherit the app input theme. Do not set custom borders.
- Grade wording comes from `reportGradeLabel` (Acceptable, Needs Improvement,
  Problematic), matching the statuses stored by the API.

## Sessions, guest data and caching

Access and refresh tokens are kept in `flutter_secure_storage`. At startup the
app exchanges the refresh token and rebuilds the session from the server
profile; expired tokens are removed, while network failures keep them and show
Retry. Logout clears tokens and keeps only the last email.

Guest results and their plots are saved in app-private storage and survive
restarts. Android backup is disabled, so clearing app data or uninstalling
removes them. Signed-in history and plots are cached per user, shown
immediately, refreshed from the server, and cleared on logout, password change
or report deletion. The server stays authoritative.

The app never contains backend secrets; only the public API URL is passed with
`--dart-define`.

## Tests

```powershell
cd frontend
flutter analyze
flutter test
```

Integration tests live in `integration_test/`. The Chrome sample-assessment
suite is described in [CHROME_TESTS.md](integration_test/CHROME_TESTS.md).

## Builds

Use the repository build script, which runs analysis and tests, signs the APK,
and writes it with a manifest to `dist/`:

```powershell
./tools/build_karaok.ps1 -PlanOnly -NonInteractive
./tools/build_karaok.ps1 -NonInteractive
```

See the [Android build guide](../build.md) for signing, AAB and version options.
Per the project rules in `AGENTS.md`, the next version is chosen from the
highest version in `dist/`, not only from `pubspec.yaml`.
