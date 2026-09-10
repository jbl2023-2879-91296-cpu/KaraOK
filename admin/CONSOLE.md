# KaraOK product administration

The console in `admin/` uses PHP 8.2, locally built Tailwind 3.4 styles, and the
Flask HTTPS administration API. PHP never connects to MySQL. Existing sign-in,
CSRF validation, machine authentication, API rate limiting, table permissions,
exact delete confirmations and audit logging remain in place.

## Run locally

With the existing API and local administrator configured:

```powershell
cd admin
composer install
npm ci
npm run css:build
php tests/run.php
composer serve
```

Open `http://127.0.0.1:8080/login`. For a fresh installation, copy `.env.example`
to `.env`, configure the HTTPS administration API URL/key, and run
`php scripts/create-admin.php admin`. Do not reuse the machine API key as the
administrator password. PHP's configured session directory must be writable.
In a restricted workspace, this alternative keeps sessions in private storage:

```powershell
php -d session.save_path=storage/private -S 127.0.0.1:8080 -t public public/router.php
```

The backend must include the new read-only routes under `/api/admin/data`:

- `/reports/overview`, `/reports/demographics`, `/reports/usage`,
  `/reports/quality`, `/reports/amplifiers`, `/reports/operations`.
- `/directory/users`, `/directory/assessments`.
- `/directory/users/<id>`, `/directory/assessments/<id>`.

An older API is detected when a new report route returns 404 while `/health`
still succeeds. The overview then uses real `/analytics` data with explicit
lifetime/rolling-window labels and administrator inclusion. Unsupported date
controls are hidden. Enhanced pages explain the missing backend capability and
link to existing record tools. Authentication, transport and server errors are
never treated as compatibility fallback; no values are invented. No deployment or database migration was performed for this work.
The reports target the current `database/schema.sql` and MySQL 8 window functions.
No new database privileges or dependencies are required.

## Pages

- **Overview:** period assessments, unique participants, registrations, completed
  and failed attempts, completion rate, scored-result mean, median completed
  processing time, preceding-period comparisons, lifetime account states, daily
  trends, upload genres and recent assessments.
- **Users:** masked contact details, age, location, verification and activation,
  registration-date filters, search, sorting, 25-row pagination, assessment counts
  and last assessment dates. Detail pages provide profile, daily score trend,
  genre usage, saved amplifier profiles and a filtered assessment-history link.
  Activation/deactivation uses the existing permitted update form.
- **Demographics:** all seven age bands plus unknown/invalid, counts, percentages,
  distinct assessment participants and top-25 country/city distributions.
- **Usage:** trailing 1/7/30-day assessment-active users, period intensity,
  first-time versus returning assessors, registration-cohort conversion and
  mean delay, daily active-user trend and weekday volume.
- **Assessments / Audio quality:** paginated searchable attempts, status and
  genre filters, recorded detail/feature/grading metadata, score distribution,
  daily completed-score means, genre score averages and failure rates.
- **Amplifier settings:** feature-flag-aware saved-profile counts, recommendation
  statuses/genres, normalized recommended knob distributions, recorded versions
  and confidence, and explicitly parent-linked verification comparisons.
- **Operations:** logged request volume/error rate/mean latency, latest 50
  failed/pending/processing attempts and latest 50 audit events. Connection
  diagnostics and controlled record management remain accessible. Technical
  schema tools are grouped under **Advanced**.

CSV exports of users and assessments use exactly the directory filters and
backend masking, return at most the first 100 records in the selected sort,
require the authenticated console session and API key, escape spreadsheet
formula prefixes, and create a local export audit event. The backend also logs
all requests. Exports are never stored publicly.

## Reporting contract

- Dates use **UTC**, independently of the PHP display timezone. Start/end are
  inclusive dates, translated to `[start, end + 1 day)` in SQL. Choose 7/30/90
  complete days or a custom 1–366-day interval ending before today. Presets and
  date filters persist through product navigation in the authenticated session.
- All product population/activity metrics use `user.role = 'user'`; deactivated
  accounts remain included. Engagement comes from stored assessments, including
  failed attempts, never account activation or administrator/background requests.
  Guest assessments remain device-local and are excluded.
- The preceding comparison covers an immediately preceding equal-length window.
  A zero/null baseline yields “Comparison unavailable,” never infinity. Percent
  comparisons are relative changes, including comparisons of percentage rates.
- Lifetime account metrics read `user`; period registrations use `created_at`.
  Counts of assessment participants use distinct user IDs. Unique assessment
  keys on result/upload joins prevent multiplication of assessment totals.
- Completion = completed / all period attempts. Average score uses non-null
  `audio_analysis_result.quality_score` for completed assessments; zero is a
  score, not missing. Median processing uses nonnegative completed assessment
  `processing_time` values, in seconds. Empty rate/average denominators are null.
- Ages use completed birthdays as of the displayed UTC reference date. Missing,
  zero, future, impossible day-of-month, or over-120 birthdays are invalid.
  Unknown users remain in the percentage denominator. Exact birthdays and full
  addresses do not appear in product views or exports. City names are grouped
  literally across countries; the interface discloses that grouping.
- Conversion uses registrations in the selected period and observes first
  assessment from registration until period end. Delay is an arithmetic mean
  over converted registrations only. Recent registrations have shorter exposure.
- Operations include all logged API traffic; HTTP 400–599 are errors. Latency
  is mean `duration_ms`. This traffic is not presented as user engagement.
- Amplifier distributions use recommended positions relative to each stored
  scale, in 10-percentage-point buckets. They do not establish physical changes.
  Verification comparisons use explicit parent/child recommendation links and
  show each linked outcome once, selected by verification child's creation date.
  Generated recommendation counts include stored verification-child records.
  Confidence/provisional status is shown as recorded, without interpretation.
- Reports execute in a read-only consistent snapshot with UTC session time and
  the existing database query timeout. Only aggregates or bounded detail rows
  leave the backend. Successful reports have a bounded, per-session 30-second
  cache; Refresh bypasses it. Failures are never cached. Browser responses use
  `Cache-Control: no-store`; the existing API does too.

## Data limitations

Deleted assessments are absent from history. Complete historical retention
cannot be established from these tables, so retention cohorts are intentionally
not presented. Gender, comprehensive guest activity, playable recordings and
report images are not exposed by this API. Loudness stores LUFS with a dBFS
fallback but no unit discriminator, so detail pages explain this ambiguity.
Distortion is an analyzer estimate, not a measured THD percentage. Scores
measure instrumental audio quality, never singing ability. Optional missing
values are marked Not collected; API or feature failures are Unavailable.

There is no new user deletion, unrestricted editing, privilege management,
automatic amplifier application or new mutation endpoint. Existing Advanced
record permissions remain defined in `admin_data/policy.py`.

## Verification

```powershell
# From the repository root
php admin/tests/run.php
npm --prefix admin run css:build
cd backend
python -m unittest tests.test_admin_data_api tests.test_admin_reports -v
```

The report suite executes joins, aggregates, pagination and window functions
against a disposable in-memory SQLite fixture with a small MySQL scalar-syntax
adapter. It tests arithmetic and inclusion rules, not full MySQL dialect/runtime
compatibility. Run a read-only staging smoke check on the target MySQL version
before deploying. Tests never connect to production MySQL.

The PHP tests cover masking of actual displayed rows, output escaping, empty
states, missing/zero metrics and CSV formula protection. Signed-in HTTP checks
were also run on an isolated copy of the console using the fixture API, covering
all product pages, details, filtered masked CSV and an invalid-date retry state.
Browser tooling reported no available browser, so desktop/narrow visual QA is
still required; responsive navigation, overflow containers and focus styles have
been implemented but are not claimed as visually verified.

`backend/tests/admin_preview_api.py` is a local-only synthetic-data API for
optional visual QA (`python -m tests.admin_preview_api` from `backend/`). It binds
127.0.0.1:8092 and cannot open MySQL or mutate records. Use only a disposable
console copy with its own private credentials/session storage, never point a
production console at it. Synthetic preview data is labelled in report metadata.

## Code organization

`public/index.php` handles routing and existing mutations. Product view helpers
are in `app/Views/product.php`, the shared shell in `app/Views/layout.php`, and
preserved technical/record views in `app/Views/legacy.php`. Backend report logic
is separate from controlled CRUD in `admin_data/reports.py`. Source CSS and
small progressive-enhancement scripts remain dependency-light; no CDN assets,
chart framework or browser machine credentials are used.
