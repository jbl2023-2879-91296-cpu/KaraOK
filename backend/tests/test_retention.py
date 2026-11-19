"""Retention cleanup deletes only expired rows, in batches, and only opted-in images."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from karaok.core.retention import (
    RetentionPolicy,
    purge_expired_records,
    purge_old_visualizations,
    run_retention,
)


class FakeCursor:
    def __init__(self, db: "FakeConnection"):
        self.db = db
        self.rowcount = 0
        self._rows: list = []

    def execute(self, sql: str, params=()):
        self.db.executed.append((" ".join(sql.split()), params))
        if sql.startswith("DELETE"):
            table = sql.split()[2]
            queue = self.db.delete_results.setdefault(table, [])
            self.rowcount = queue.pop(0) if queue else 0
        elif sql.startswith("SELECT COUNT"):
            self._rows = [(self.db.counts.get(sql.split()[3], 0),)]
        elif "FROM audio_analysis_result" in sql and sql.lstrip().startswith("SELECT"):
            self._rows = self.db.visual_batches.pop(0) if self.db.visual_batches else []
        elif sql.lstrip().startswith("UPDATE"):
            self.db.cleared.append(params[0])

    def fetchone(self):
        return self._rows[0]

    def fetchall(self):
        return self._rows

    def close(self):
        pass


class FakeConnection:
    def __init__(self):
        self.executed: list = []
        self.delete_results: dict[str, list[int]] = {}
        self.counts: dict[str, int] = {}
        self.visual_batches: list = []
        self.cleared: list = []
        self.commits = 0

    def cursor(self):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1


class RetentionPolicyTests(unittest.TestCase):
    def test_rejects_negative_days(self):
        with self.assertRaises(ValueError):
            RetentionPolicy(request_log_days=-1)

    def test_rejects_zero_batch(self):
        with self.assertRaises(ValueError):
            RetentionPolicy(batch_size=0)

    def test_images_are_kept_by_default(self):
        self.assertEqual(RetentionPolicy().visualization_days, 0)


class PurgeExpiredRecordsTests(unittest.TestCase):
    def test_deletes_in_batches_until_a_short_batch(self):
        db = FakeConnection()
        db.delete_results["api_request_log"] = [2, 2, 1]
        deleted = purge_expired_records(db, RetentionPolicy(batch_size=2))
        self.assertEqual(deleted["api_request_log"], 5)
        log_deletes = [p for s, p in db.executed if s.startswith("DELETE FROM api_request_log")]
        self.assertEqual(log_deletes, [(90,), (90,), (90,)])
        self.assertTrue(all("LIMIT 2" in s for s, _ in db.executed if s.startswith("DELETE")))

    def test_uses_configured_windows_and_one_day_credential_grace(self):
        db = FakeConnection()
        purge_expired_records(db, RetentionPolicy(request_log_days=30, audit_log_days=400))
        params = {s.split()[2]: p for s, p in db.executed}
        self.assertEqual(params["api_request_log"], (30,))
        self.assertEqual(params["audit_log"], (400,))
        for table in ("refresh_token", "revoked_access_token", "registration_otp"):
            self.assertEqual(params[table], (1,))

    def test_zero_window_skips_that_table(self):
        db = FakeConnection()
        deleted = purge_expired_records(db, RetentionPolicy(audit_log_days=0))
        self.assertNotIn("audit_log", deleted)
        self.assertFalse(any("audit_log" in s for s, _ in db.executed))

    def test_never_touches_results_or_users(self):
        db = FakeConnection()
        purge_expired_records(db, RetentionPolicy())
        for sql, _ in db.executed:
            for table in ("assessment", "audio_analysis_result", "audio_upload", "user ",
                          "settings_recommendation", "amplifier_profile"):
                self.assertNotIn(f"FROM {table}", sql)

    def test_dry_run_counts_without_deleting(self):
        db = FakeConnection()
        db.counts["api_request_log"] = 7
        deleted = purge_expired_records(db, RetentionPolicy(), dry_run=True)
        self.assertEqual(deleted["api_request_log"], 7)
        self.assertFalse(any(s.startswith("DELETE") for s, _ in db.executed))
        self.assertEqual(db.commits, 0)


class PurgeVisualizationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "1" / "1").mkdir(parents=True)
        self.wave = self.root / "1" / "1" / "a_waveform.png"
        self.spec = self.root / "1" / "1" / "a_spectrogram.png"
        self.wave.write_bytes(b"png")
        self.spec.write_bytes(b"png")

    def test_disabled_by_default(self):
        db = FakeConnection()
        self.assertEqual(purge_old_visualizations(db, RetentionPolicy(), self.root), (0, 0))
        self.assertEqual(db.executed, [])
        self.assertTrue(self.wave.exists())

    def test_removes_files_and_clears_paths(self):
        db = FakeConnection()
        db.visual_batches = [[(11, "1/1/a_waveform.png", "1/1/a_spectrogram.png")]]
        cleared, removed = purge_old_visualizations(
            db, RetentionPolicy(visualization_days=180), self.root
        )
        self.assertEqual((cleared, removed), (1, 2))
        self.assertFalse(self.wave.exists())
        self.assertFalse(self.spec.exists())
        self.assertEqual(db.cleared, [11])

    def test_refuses_paths_outside_the_output_root(self):
        outside = self.root.parent / "outside_retention_test.png"
        outside.write_bytes(b"keep")
        self.addCleanup(lambda: outside.unlink(missing_ok=True))
        db = FakeConnection()
        db.visual_batches = [[(12, "../outside_retention_test.png", None)]]
        purge_old_visualizations(db, RetentionPolicy(visualization_days=1), self.root)
        self.assertTrue(outside.exists())

    def test_dry_run_keeps_files(self):
        db = FakeConnection()
        db.visual_batches = [[(11, "1/1/a_waveform.png", "1/1/a_spectrogram.png")]]
        cleared, removed = purge_old_visualizations(
            db, RetentionPolicy(visualization_days=1), self.root, dry_run=True
        )
        self.assertEqual((cleared, removed), (1, 2))
        self.assertTrue(self.wave.exists())
        self.assertEqual(db.cleared, [])

    def test_run_retention_reports_everything(self):
        db = FakeConnection()
        report = run_retention(db, RetentionPolicy(), self.root)
        self.assertIn("api_request_log", report.deleted)
        self.assertTrue(any(line.startswith("visualizations:") for line in report.lines()))


if __name__ == "__main__":
    unittest.main()
