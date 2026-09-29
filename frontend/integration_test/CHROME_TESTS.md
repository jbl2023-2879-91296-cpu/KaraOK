# Chrome sample-assessment checks

The sample suite runs in real Chrome using Flutter integration_test and a ChromeDriver matching the installed Chrome version. It uses actual browser guest storage. Account history and the completed audio response are fixtures; this suite does not upload audio or contact the assessment backend.

Start ChromeDriver in a separate terminal:

```powershell
chromedriver --port=4444
```

From `frontend`:

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/chrome_sample_assessments_test.dart -d web-server --browser-name=chrome --no-web-resources-cdn --no-pub
```

For a phone-sized Chrome viewport, add `--browser-dimension=390x844`.

Coverage:
- All three guest samples open the real results screen without consuming allowance or saving reports.
- Permanent light theme and guest Home Sign in / Create Account navigation.
- A completed guest report and its images persist through a fresh store instance and replace samples on Home and Records.
- An empty account shows samples, and a refreshed real assessment replaces them.

The driver uses an isolated browser session. Test setup and teardown clear only that session's guest reports and guest allowance. Reload/restart durability and live backend audio evaluation are outside this suite.
