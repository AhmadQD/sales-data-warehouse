#!/usr/bin/env bash
# ============================================================
# backup.sh — PostgreSQL backup for sales-data-warehouse
#
# What it does:
#   1. Creates the backups/ directory if missing.
#   2. Dumps roles (pg_dumpall --roles-only) to roles_<ts>.sql.
#   3. Dumps the database (pg_dump -Fc) to sales_dw_<ts>.dump.
#   4. Verifies the dump can be listed by pg_restore.
#   5. Removes backups older than RETENTION (default: 7).
#   6. Prints a summary.
#
# Usage:
#   bash scripts/backup/backup.sh
#
# Config via environment variables (with defaults):
#   DB_NAME      (default: sales_dw)
#   DB_USER      (default: postgres)
#   BACKUP_DIR   (default: ./backups)
#   RETENTION    (default: 7)
#   PGHOST, PGPORT, PGPASSWORD — standard libpq variables
#
# NOTE: For a production deployment, add:
#   - encryption (gpg)
#   - off-site copy (aws s3 cp, rclone)
#   - restore drill (weekly test restore)
# See docs/backup_strategy.md
# ============================================================

set -euo pipefail

DB_NAME="${DB_NAME:-sales_dw}"
DB_USER="${DB_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION="${RETENTION:-7}"

TS="$(date +%Y-%m-%d_%H-%M-%S)"
DUMP_FILE="${BACKUP_DIR}/sales_dw_${TS}.dump"
ROLES_FILE="${BACKUP_DIR}/roles_${TS}.sql"

# ------------------------------------------------------------------
# 0. Sanity checks
# ------------------------------------------------------------------
if ! command -v pg_dump >/dev/null 2>&1; then
    echo "ERROR: pg_dump not found in PATH." >&2
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

echo "============================================================"
echo "  BACKUP — ${DB_NAME}"
echo "  Timestamp : ${TS}"
echo "  Target    : ${DUMP_FILE}"
echo "============================================================"

# ------------------------------------------------------------------
# 1. Roles
# ------------------------------------------------------------------
echo ""
echo ">>> Dumping roles..."
pg_dumpall --roles-only -U "${DB_USER}" -f "${ROLES_FILE}"
ROLES_SIZE="$(du -h "${ROLES_FILE}" | cut -f1)"
echo "    OK: ${ROLES_FILE} (${ROLES_SIZE})"

# ------------------------------------------------------------------
# 2. Database
# ------------------------------------------------------------------
echo ""
echo ">>> Dumping database..."
pg_dump -U "${DB_USER}" -d "${DB_NAME}" -Fc -f "${DUMP_FILE}"
DUMP_SIZE="$(du -h "${DUMP_FILE}" | cut -f1)"
echo "    OK: ${DUMP_FILE} (${DUMP_SIZE})"

# ------------------------------------------------------------------
# 3. Verify
# ------------------------------------------------------------------
echo ""
echo ">>> Verifying dump (pg_restore --list)..."
if pg_restore --list "${DUMP_FILE}" >/dev/null 2>&1; then
    echo "    OK: dump is valid."
else
    echo "    FAIL: dump is corrupt or unreadable." >&2
    exit 1
fi

# ------------------------------------------------------------------
# 4. Retention
# ------------------------------------------------------------------
echo ""
echo ">>> Applying retention (keep last ${RETENTION})..."
DUMP_COUNT="$(ls -1 "${BACKUP_DIR}"/sales_dw_*.dump 2>/dev/null | wc -l)"
if [ "${DUMP_COUNT}" -gt "${RETENTION}" ]; then
    # Sort by name (timestamp-sortable) ascending, drop the oldest.
    ls -1 "${BACKUP_DIR}"/sales_dw_*.dump \
        | sort \
        | head -n -"${RETENTION}" \
        | while read -r old; do
            echo "    Removing old backup: ${old}"
            rm -f "${old}"
        done
else
    echo "    Nothing to remove (${DUMP_COUNT} <= ${RETENTION})."
fi

# Roles files: keep only the latest
ROLES_COUNT="$(ls -1 "${BACKUP_DIR}"/roles_*.sql 2>/dev/null | wc -l)"
if [ "${ROLES_COUNT}" -gt 1 ]; then
    ls -1 "${BACKUP_DIR}"/roles_*.sql \
        | sort \
        | head -n -1 \
        | while read -r old; do
            echo "    Removing old roles file: ${old}"
            rm -f "${old}"
        done
fi

# ------------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  SUMMARY"
echo "  Total dumps kept : $(ls -1 "${BACKUP_DIR}"/sales_dw_*.dump 2>/dev/null | wc -l)"
echo "  Total size       : $(du -sh "${BACKUP_DIR}" | cut -f1)"
echo "============================================================"
echo "Done."
