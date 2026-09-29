# Sample Assessments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provide three disposable demonstration assessments until the first real record, plus guest Home sign-in.
**Architecture:** A presentation-only sample catalog decorates successfully loaded empty histories. Home and Records share the catalog and open the existing ResultsScreen with explicit sample state.
**Tech Stack:** Flutter/Dart; existing guest store, API/cache, widget tests.
**Spec:** docs/superpowers/specs/2026-09-29-sample-assessments.md

## Global Constraints
- Exactly three samples; never persist or count them as evaluations.
- Only confirmed empty history permits samples; real history takes precedence.
- Guest and authenticated histories remain separate; no theme toggle.

## Review Focus
- Failed API loads: show error, not samples.
- Filtering real records to zero: no samples appear.
- First real guest assessment: refresh replaces all examples.
- Sample detail navigation: no completion claim, no fake network visualization fetch.
- Narrow guest banner: both auth actions remain usable.

### Task 1: Sample catalog and detail mode
**Files:** new reports/domain/sample_assessments.dart; reports/presentation/pages/results_screen.dart; test/reports/sample_assessments_test.dart.
**Interfaces:** `assessmentHistoryForDisplay(List<dynamic>)` returns original nonempty history or three immutable sample maps; `isSampleAssessment(Map)` identifies samples. ResultsScreen.fromRecord propagates sample state.
- [x] Write tests for three examples, real-record precedence, and sample details using the real results widget without completion messaging.
- [x] Run tests and verify expected failures.
- [x] Implement catalog and explicit sample detail state; keep native back navigation for samples.
- [x] Run focused tests.

### Task 2: Home and Records empty-history integration
**Files:** home/presentation/pages/user_home_screen.dart; reports/presentation/pages/previous_results_screen.dart; app/app_shell.dart; test/reports/sample_assessments_test.dart; test/widget_test.dart.
**Interfaces:** optional Home resultsLoader parallels Records resultsLoader; both decorate only successful histories. Records reload token increments when tab selected.
- [x] Test empty guest/account history, first real record replacement, errors, filter-to-empty, and Home sample links.
- [x] Run failing tests, then integrate catalog in successful load paths; exclude empty caches until server confirms empty.
- [x] Display sample explanation and omit stored-guest-report prompt for samples; refresh on Records activation.
- [x] Update superseded empty-state assertions and run affected tests.

### Task 3: Guest sign-in and validation
**Files:** shared/widgets/guest_banner.dart; test/reports/sample_assessments_test.dart.
- [x] Test adjacent auth actions, navigation, and narrow-width layout.
- [x] Add optional Sign in action on Home with wrapping controls.
- [x] Run full Flutter test suite, analyzer, web build, and independent review.

## Execution ledger
- Ruling: user full autonomy overrides intermediate design/plan approval pauses; implementation stays inline.
- Ruling: no sample graphs without real graph assets; demonstrate supported numeric assessment UI and mark every sample clearly.

- Review: guest history corruption was incorrectly treated as empty; added regression coverage and propagated read/format errors.
- Ruling: guest used-evaluation count also suppresses samples when an older report is unavailable.
- Ruling: sample score detail inherits the existing result layout; explicit sample subtitle replaces saved-reference claims.
- Test infrastructure: new Home disk reads require alternating widget frames with real IO waits in navigation tests.
- Visual QA: rendered Home and sample Results at 390x844; inspected both. Temporary render harness removed; previews in output/sample-preview/.
- Verification: analyzer clean; production web build successful; final full-suite result recorded below.
- Delivery: preserve local uncommitted branding and sample changes on feat/light-theme-branding; no merge or push requested.
- Final verification: 157 Flutter tests passed; flutter analyze reported no issues; flutter build web completed successfully.

- Chrome follow-up: reproduced MissingPluginException from native path_provider guest history; web guest reports now use browser-backed FlutterSecureStorage, including visualization data. Native storage remains covered by the existing suite.
- Chrome desktop verification: four integration cases passed using ChromeDriver 153; real browser guest storage, sample detail/navigation, auth links, guest replacement, and fixture-backed account replacement.
- Chrome follow-up verification: 157 standard Flutter tests passed; analyzer clean. Repeatable command and test limits are documented in frontend/integration_test/CHROME_TESTS.md.
- Chrome compact verification: the same four integration cases passed at 390x844; desktop and compact runs both exited 0.
