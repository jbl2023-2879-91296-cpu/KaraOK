#!/usr/bin/env bash
set -euo pipefail

backup_root=/var/backups/karaok
upload_root=/var/lib/karaok/uploads
stamp=$(date -u +%Y%m%dT%H%M%SZ)
run_dir="$backup_root/$stamp"

install -d -m 0700 "$run_dir"
mysqldump --single-transaction --routines --triggers karaok_db | gzip -9 > "$run_dir/karaok_db.sql.gz"

if find "$upload_root" -mindepth 1 -print -quit | grep -q .; then
    tar -C "$upload_root" -czf "$run_dir/uploads.tar.gz" .
fi

sha256sum "$run_dir"/* > "$run_dir/SHA256SUMS"
find "$backup_root" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf -- {} +
echo "Backup completed: $run_dir"
