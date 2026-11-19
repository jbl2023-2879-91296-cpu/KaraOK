"""Delete old log rows, expired credentials and (optionally) old report images.

Windows are read from backend/.env (or KARAOK_ENV_FILE) and can be overridden:

    python scripts/purge_old_records.py --dry-run
    python scripts/purge_old_records.py
    python scripts/purge_old_records.py --request-log-days 30 --visualization-days 180

REQUEST_LOG_RETENTION_DAYS   api_request_log rows to keep (default 90)
AUDIT_LOG_RETENTION_DAYS     audit_log rows to keep (default 365)
VISUALIZATION_RETENTION_DAYS waveform/spectrogram PNGs to keep (default 0 = keep all)

Expired refresh tokens, revoked access tokens and unused sign-up codes are
always removed one day after they expire. Scores and analysis details are never
deleted by this script.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from karaok.core import config  # noqa: E402
from karaok.core.database import get_db  # noqa: E402
from karaok.core.retention import RetentionPolicy, run_retention  # noqa: E402


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="count only, delete nothing")
    parser.add_argument("--request-log-days", type=int, default=config.REQUEST_LOG_RETENTION_DAYS)
    parser.add_argument("--audit-log-days", type=int, default=config.AUDIT_LOG_RETENTION_DAYS)
    parser.add_argument("--visualization-days", type=int, default=config.VISUALIZATION_RETENTION_DAYS)
    parser.add_argument("--batch-size", type=int, default=5000)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        policy = RetentionPolicy(
            request_log_days=args.request_log_days,
            audit_log_days=args.audit_log_days,
            visualization_days=args.visualization_days,
            batch_size=args.batch_size,
        )
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    connection = get_db()
    try:
        report = run_retention(
            connection, policy, config.ANALYSIS_OUTPUT_DIR, dry_run=args.dry_run
        )
    finally:
        connection.close()
    prefix = "would delete" if args.dry_run else "deleted"
    for line in report.lines():
        print(f"{prefix} {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
