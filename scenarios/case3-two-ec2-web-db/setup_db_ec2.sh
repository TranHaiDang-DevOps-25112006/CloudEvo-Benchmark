#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "=========================================================="
echo "[START] Khởi tạo DB EC2 (Case 3) lúc: $(date -u)"
echo "=========================================================="

# Thông số cấu hình
DB_NAME="cloudevo_db"
DB_USER="cloudevo"
DB_PASS="CloudEvo@2026"
S3_BUCKET="cloudevo-backup-dangth"
VPC_CIDR="10.0.0.0/16"

# 1. Cập nhật hệ thống và cài đặt PostgreSQL + AWS CLI
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y postgresql postgresql-contrib awscli curl jq

# 2. Cấu hình postgresql.conf và pg_hba.conf cho phép Web EC2 trong VPC kết nối
PG_VERSION=$(ls /etc/postgresql/ | head -n 1)
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

if ! grep -q "$VPC_CIDR" "$PG_HBA"; then
    echo "# Allow CloudEvo Web EC2 in VPC" >> "$PG_HBA"
    echo "host    all             all             ${VPC_CIDR}            scram-sha-256" >> "$PG_HBA"
fi

systemctl restart postgresql
systemctl enable postgresql

# 3. Khởi tạo User, Database và Bảng dữ liệu mẫu
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';
   END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

sudo -u postgres psql -d "${DB_NAME}" <<EOF
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    customer VARCHAR(100) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
GRANT ALL PRIVILEGES ON TABLE transactions TO ${DB_USER};
GRANT USAGE, SELECT ON SEQUENCE transactions_id_seq TO ${DB_USER};

INSERT INTO transactions (customer, amount)
SELECT 'Case 3 Initial Seed (Decoupled DB EC2)', 250.00
WHERE NOT EXISTS (SELECT 1 FROM transactions LIMIT 1);
EOF

# 4. Tạo script Backup lên S3 (chạy qua S3 Gateway Endpoint không cần Internet)
cat << 'EOF' > /usr/local/bin/backup_s3.sh
#!/bin/bash
set -e
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/tmp/db_backups"
S3_BUCKET="cloudevo-backup-dangth"
DB_NAME="cloudevo_db"

mkdir -p "$BACKUP_DIR"
FILE_PATH="${BACKUP_DIR}/case3_${DB_NAME}_${TIMESTAMP}.sql.gz"

echo "[BACKUP] Đang dump dữ liệu PostgreSQL..."
sudo -u postgres pg_dump "$DB_NAME" | gzip > "$FILE_PATH"
cp "$FILE_PATH" "${BACKUP_DIR}/case3_latest.sql.gz"

echo "[BACKUP] Đang đẩy file lên s3://${S3_BUCKET}/case3/ ..."
aws s3 cp "$FILE_PATH" "s3://${S3_BUCKET}/case3/case3_${DB_NAME}_${TIMESTAMP}.sql.gz" --region ap-southeast-1
aws s3 cp "${BACKUP_DIR}/case3_latest.sql.gz" "s3://${S3_BUCKET}/case3/case3_latest.sql.gz" --region ap-southeast-1

echo "[SUCCESS] Hoàn tất backup Case 3 lên S3 lúc $(date)!"
EOF
chmod +x /usr/local/bin/backup_s3.sh

# 5. Tạo script Restore từ S3 (dùng cho bài Test 3B)
cat << 'EOF' > /usr/local/bin/restore_s3.sh
#!/bin/bash
set -e
S3_BUCKET="cloudevo-backup-dangth"
DB_NAME="cloudevo_db"
DB_USER="cloudevo"
RESTORE_FILE="/tmp/case3_restore.sql.gz"

echo "[RESTORE] Đang tải bản backup mới nhất từ S3..."
aws s3 cp "s3://${S3_BUCKET}/case3/case3_latest.sql.gz" "$RESTORE_FILE" --region ap-southeast-1

echo "[RESTORE] Đang khởi động lại PostgreSQL và nạp lại dữ liệu..."
systemctl start postgresql
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME} WITH (FORCE);"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
gunzip -c "$RESTORE_FILE" | sudo -u postgres psql -d "${DB_NAME}"
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER}; GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};"

echo "[SUCCESS] Khôi phục Database tầng DB EC2 thành công lúc $(date)!"
EOF
chmod +x /usr/local/bin/restore_s3.sh

# Đăng ký Cronjob tự động backup mỗi 1 giờ
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/backup_s3.sh >> /var/log/backup_s3.log 2>&1") | crontab -

echo "=========================================================="
echo "[DONE] Hoàn tất cài đặt DB EC2 lúc: $(date -u)"
echo "=========================================================="