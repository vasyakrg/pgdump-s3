#!/usr/bin/env sh

set -e

BACKUP_DIR="/tmp"
SQL_NAME="backup.dump"
SQL_PATH="${BACKUP_DIR}/${SQL_NAME}"
PGDUMP_CMD="$(python3 /usr/local/bin/pguri ${SQL_PATH})"
BACKUP_NAME="$(date -u +%Y-%m-%d_%H-%M-%S)_UTC.tar.gz"
AWS_CMD="aws"

# Add S3_ENDPOINT if set to AWS command
if [[ ${S3_ENDPOINT} ]]; then
  AWS_CMD="aws --endpoint=${S3_ENDPOINT}"
fi

# Run backup
eval $PGDUMP_CMD

# Compress backup
tar -cvzf "${BACKUP_DIR}/${BACKUP_NAME}" -C "${BACKUP_DIR}" "${SQL_NAME}"

# Upload backup
$AWS_CMD s3 cp "${BACKUP_DIR}/${BACKUP_NAME}" "s3://${S3_BUCKET}${S3_PATH}/${BACKUP_NAME}"

# Delete temp files
rm -rf "${SQL_PATH}" "${BACKUP_DIR}/${BACKUP_NAME}"
