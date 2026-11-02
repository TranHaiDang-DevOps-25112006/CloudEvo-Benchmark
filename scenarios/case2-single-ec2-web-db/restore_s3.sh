#!/bin/bash
# Khôi phục PostgreSQL (Case 2) từ bản backup mới nhất trên S3.
# Bản dump được tạo với --clean --if-exists nên restore thành công sẽ xóa bảng hiện tại và nạp lại dữ liệu từ dump.
set -e
S3_BUCKET="${S3_BUCKET:-cloudevo-backup-dangth}"

echo "[$(date)] Đang tải bản backup mới nhất từ s3://${S3_BUCKET}/case2/latest.sql.gz..."
aws s3 cp "s3://${S3_BUCKET}/case2/latest.sql.gz" /tmp/latest.sql.gz

# Dừng Web App trong lúc nạp dữ liệu để tránh việc ứng dụng tự khởi tạo dữ liệu mẫu trước khi restore
echo "[$(date)] Dừng Web App trong lúc nạp dữ liệu..."
docker stop cloudevo-web || true

echo "[$(date)] Đang nạp lại dữ liệu vào PostgreSQL..."
gunzip -c /tmp/latest.sql.gz | docker exec -i cloudevo-postgres psql -U cloudevo_user -d cloudevo_db
rm -f /tmp/latest.sql.gz
docker start cloudevo-web || true

echo "[$(date)] KHÔI PHỤC DỮ LIỆU TỪ S3 THÀNH CÔNG! Hãy kiểm tra lại số bản ghi và timestamp."
