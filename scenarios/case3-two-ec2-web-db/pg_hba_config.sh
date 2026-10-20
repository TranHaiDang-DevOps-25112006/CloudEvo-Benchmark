#!/bin/bash
set -e

PG_VERSION=$(ls /etc/postgresql/ | head -n 1)
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"
VPC_CIDR="10.0.0.0/16"

echo "[INFO] Đang cấu hình PostgreSQL ${PG_VERSION} cho phép kết nối từ VPC (${VPC_CIDR})..."

# 1. Cho phép PostgreSQL lắng nghe trên tất cả các interface nội bộ
sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# 2. Thêm rule vào pg_hba.conf cho phép Web EC2 trong dải VPC 10.0.0.0/16 kết nối
if ! grep -q "$VPC_CIDR" "$PG_HBA"; then
    echo "" >> "$PG_HBA"
    echo "# CloudEvo Case 3: Allow connections from Web EC2 inside cloudevo-vpc" >> "$PG_HBA"
    echo "host    all             all             ${VPC_CIDR}            scram-sha-256" >> "$PG_HBA"
fi

# 3. Khởi động lại PostgreSQL để áp dụng cấu hình
systemctl restart postgresql
systemctl enable postgresql

echo "[SUCCESS] Đã mở kết nối PostgreSQL cổng 5432 cho nội bộ VPC ${VPC_CIDR}!"
ss -tulpn | grep 5432