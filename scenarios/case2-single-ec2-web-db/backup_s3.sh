#!/bin/bash
set -e

# Thay tên S3 Bucket của bạn vào biến bên dưới (hoặc truyền qua biến môi trường)
S3_BUCKET="${S3_BUCKET:-cloudevo-backup-dangth}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/tmp/db_backups"
BACKUP_FILE="${BACKUP_DIR}/cloudevo_db_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Bắt đầu xuất dữ liệu PostgreSQL (pg_dump)..."
docker exec cloudevo-postgres pg_dump -U cloudevo_user -d cloudevo_db | gzip > "$BACKUP_FILE"

echo "[$(date)] Đang tải bản sao lưu lên S3: s3://${S3_BUCKET}/case2/"
aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/case2/cloudevo_db_${TIMESTAMP}.sql.gz"
aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/case2/latest.sql.gz"

# Xóa file tạm trên ổ cứng EC2 để tránh đầy EBS
rm -f "$BACKUP_FILE"
echo "[$(date)] HOÀN TẤT BACKUP: s3://${S3_BUCKET}/case2/cloudevo_db_${TIMESTAMP}.sql.gz"