#!/bin/bash
# Script tự động hóa kiểm thử Multi-AZ Failover & Point-in-Time Recovery (PITR) cho Trường hợp 4
REGION="ap-southeast-1"
DB_INSTANCE_ID="cloudevo-rds-postgres"
RESTORE_INSTANCE_ID="cloudevo-rds-pitr-restore"

echo "================================================================"
echo " [TEST 4A] KÍCH HOẠT RDS MULTI-AZ REBOOT WITH FAILOVER"
echo "================================================================"
echo "-> Đang gửi lệnh Force Failover tới RDS instance: $DB_INSTANCE_ID ..."

aws rds reboot-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --force-failover \
  --region "$REGION"

echo "-> Đã kích hoạt Failover! Hãy quan sát cửa sổ chạy scripts/dr_monitor.py"
echo "-> Đang theo dõi trạng thái chuyển đổi AZ của RDS mỗi 5 giây:"

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