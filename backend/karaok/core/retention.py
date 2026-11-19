"""Retention cleanup for tables and files that grow without bound.

Run nightly through ``backend/scripts/purge_old_records.py``. Every DELETE runs in
small batches so a large backlog never holds long row locks on a live server.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from karaok.core.paths import ensure_within_root

DEFAULT_BATCH_SIZE = 5000
# Expired credentials are kept one extra day so a token that expires mid-request
# is still found and rejected as expired rather than as unknown.
EXPIRED_CREDENTIAL_GRACE_DAYS = 1


@dataclass(frozen=True)
class RetentionPolicy:
    """Days to keep each kind of record. ``0`` disables that cleanup."""

    request_log_days: int = 90
    audit_log_days: int = 365
    visualization_days: int = 0
    batch_size: int = DEFAULT_BATCH_SIZE

    def __post_init__(self) -> None:
        for name in ("request_log_days", "audit_log_days", "visualization_days"):
            value = getattr(self, name)
            if not isinstance(value, int) or value < 0:
                raise ValueError(f"{name} must be a whole number of days, 0 or more")
        if not isinstance(self.batch_size, int) or self.batch_size < 1:
            raise ValueError("batch_size must be at least 1")


@dataclass
class RetentionReport:
    deleted: dict[str, int] = field(default_factory=dict)
    visualization_files_removed: int = 0
    visualization_rows_cleared: int = 0

    def lines(self) -> list[str]:
        rows = [f"{table}: {count} row(s)" for table, count in self.deleted.items()]
        rows.append(
            "visualizations: "
            f"{self.visualization_rows_cleared} result(s) cleared, "
            f"{self.visualization_files_removed} file(s) removed"
        )
        return rows


# Each statement selects rows by an indexed timestamp column. ``{limit}`` is an
# integer formatted in by the caller; ``%s`` is the retention window in days.
_PURGES: tuple[tuple[str, str, str], ...] = (
    (
        "api_request_log",
        "request_log_days",
        "DELETE FROM api_request_log "
        "WHERE created_at < UTC_TIMESTAMP() - INTERVAL %s DAY LIMIT {limit}",
    ),
    (
        "audit_log",
        "audit_log_days",
        "DELETE FROM audit_log "
        "WHERE created_at < UTC_TIMESTAMP() - INTERVAL %s DAY LIMIT {limit}",
    ),
    (
        "refresh_token",
        "",
        "DELETE FROM refresh_token "
        "WHERE expires_at < UTC_TIMESTAMP() - INTERVAL %s DAY LIMIT {limit}",
    ),
    (
        "revoked_access_token",
        "",
        "DELETE FROM revoked_access_token "
        "WHERE expires_at < UTC_TIMESTAMP() - INTERVAL %s DAY LIMIT {limit}",
    ),
    (
        "registration_otp",
        "",
        "DELETE FROM registration_otp "
        "WHERE expires_at < UTC_TIMESTAMP() - INTERVAL %s DAY LIMIT {limit}",
    ),
)

_COUNTS = {
    table: statement.replace("DELETE FROM", "SELECT COUNT(*) FROM", 1).replace(
        " LIMIT {limit}", ""
    )
    for table, _, statement in _PURGES
}


def _window_days(policy: RetentionPolicy, attribute: str) -> int:
    if not attribute:
        return EXPIRED_CREDENTIAL_GRACE_DAYS
    return getattr(policy, attribute)


def purge_expired_records(
    connection: Any,
    policy: RetentionPolicy,
    *,
    dry_run: bool = False,
) -> dict[str, int]:
    """Delete log rows past their window and credentials past their expiry."""
    deleted: dict[str, int] = {}
    cursor = connection.cursor()
    try:
        for table, attribute, statement in _PURGES:
            days = _window_days(policy, attribute)
            if days == 0:
                continue
            if dry_run:
                cursor.execute(_COUNTS[table], (days,))
                deleted[table] = int(cursor.fetchone()[0])
                continue
            total = 0
            batch_sql = statement.format(limit=int(policy.batch_size))
            while True:
                cursor.execute(batch_sql, (days,))
                affected = int(cursor.rowcount or 0)
                connection.commit()
                total += affected
                if affected < policy.batch_size:
                    break
            deleted[table] = total
    finally:
        cursor.close()
    return deleted


def purge_old_visualizations(
    connection: Any,
    policy: RetentionPolicy,
    analysis_output_dir: str | Path,
    *,
    dry_run: bool = False,
) -> tuple[int, int]:
    """Remove waveform/spectrogram PNGs for results older than the window.

    The score, features and JSON details stay; only the images go, and their
    paths are set to NULL so the API answers 404 instead of a broken file.
    Returns ``(results_cleared, files_removed)``.
    """
    if policy.visualization_days == 0:
        return 0, 0
    root = Path(analysis_output_dir).resolve()
    cleared = 0
    removed = 0
    cursor = connection.cursor()
    try:
        while True:
            cursor.execute(
                f"""SELECT r.result_id, r.waveform_path, r.spectrogram_path
                    FROM audio_analysis_result r
                    JOIN assessment a ON a.assessment_id = r.assessment_id
                    WHERE a.assessment_date < UTC_TIMESTAMP() - INTERVAL %s DAY
                      AND (r.waveform_path IS NOT NULL OR r.spectrogram_path IS NOT NULL)
                    ORDER BY r.result_id
                    LIMIT {int(policy.batch_size)}""",
                (policy.visualization_days,),
            )
            rows = cursor.fetchall()
            if not rows:
                break
            for result_id, *paths in rows:
                for relative in paths:
                    if not isinstance(relative, str) or not relative:
                        continue
                    try:
                        artifact = ensure_within_root(root, root / relative)
                    except RuntimeError:
                        continue
                    if artifact.is_file():
                        if not dry_run:
                            artifact.unlink(missing_ok=True)
                        removed += 1
                if not dry_run:
                    cursor.execute(
                        """UPDATE audio_analysis_result
                           SET waveform_path = NULL, spectrogram_path = NULL
                           WHERE result_id = %s""",
                        (result_id,),
                    )
                cleared += 1
            if dry_run:
                break
            connection.commit()
            if len(rows) < policy.batch_size:
                break
    finally:
        cursor.close()
    return cleared, removed


def run_retention(
    connection: Any,
    policy: RetentionPolicy,
    analysis_output_dir: str | Path,
    *,
    dry_run: bool = False,
) -> RetentionReport:
    report = RetentionReport()
    report.deleted = purge_expired_records(connection, policy, dry_run=dry_run)
    cleared, removed = purge_old_visualizations(
        connection, policy, analysis_output_dir, dry_run=dry_run
    )
    report.visualization_rows_cleared = cleared
    report.visualization_files_removed = removed
    return report
