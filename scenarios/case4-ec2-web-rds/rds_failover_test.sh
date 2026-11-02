#!/bin/bash
# Script kiểm thử gián đoạn Database & Point-in-Time Recovery (PITR) cho Trường hợp 4
# - Instance Single-AZ (cấu hình đã triển khai trong lab): reboot thường.
# - Instance Multi-AZ: reboot with failover (--force-failover chỉ hợp lệ với Multi-AZ).
REGION="ap-southeast-1"
DB_INSTANCE_ID="cloudevo-rds-postgres"
RESTORE_INSTANCE_ID="cloudevo-rds-pitr-restore"

echo "================================================================"
echo " [TEST 4A] KÍCH HOẠT RDS REBOOT (Single-AZ) HOẶC REBOOT WITH FAILOVER (Multi-AZ)"
echo "================================================================"
MULTI_AZ=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION" \
  --query "DBInstances[0].MultiAZ" \
  --output text)

if [[ "$MULTI_AZ" == "True" ]]; then
  echo "-> Instance là Multi-AZ: gửi lệnh reboot with failover tới $DB_INSTANCE_ID ..."
  aws rds reboot-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --force-failover \
    --region "$REGION"
else
  echo "-> Instance là Single-AZ: gửi lệnh reboot thường tới $DB_INSTANCE_ID (không có failover) ..."
  aws rds reboot-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --region "$REGION"
fi

echo "-> Đã gửi lệnh! Hãy quan sát cửa sổ chạy scripts/dr_monitor.py"
echo "-> Đang theo dõi trạng thái RDS mỗi 5 giây:"

while true; do
  STATUS_INFO=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --region "$REGION" \
    --query "DBInstances[0].[DBInstanceStatus,AvailabilityZone,SecondaryAvailabilityZone]" \
    --output text)
  echo "[$(date '+%H:%M:%S')] RDS Status | Primary AZ | Standby AZ => $STATUS_INFO"
  if [[ "$STATUS_INFO" == *"available"* ]]; then
    echo "=> RDS đã trở lại trạng thái AVAILABLE trên AZ mới!"
    break
  fi
  sleep 5
done