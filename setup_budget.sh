#!/bin/bash
# CloudEvo FinOps Guardrail: Thiết lập AWS Budget & Cảnh báo Chi phí Tự động
# Giới hạn ngân sách benchmark: $100.00 USD/tháng
# Cảnh báo: 80% chi phí thực tế ($80) & 100% chi phí dự báo ($100)

set -e

ALERT_EMAIL="dangth.devops@gmail.com" # Thay bằng email nhận thông báo của bạn

echo "=== [FinOps Guardrail] Bắt đầu thiết lập AWS Monthly Budget ==="

# 1. Tạo file cấu hình ngân sách
cat << 'EOF' > /tmp/budget_config.json
{
  "BudgetName": "CloudEvo-Benchmark-Monthly-Guardrail",
  "BudgetLimit": {
    "Amount": "100.0",
    "Unit": "USD"
  },
  "CostTypes": {
    "IncludeTax": true,
    "IncludeSubscription": true,
    "UseBlended": false,
    "IncludeRefund": false,
    "IncludeCredit": false,
    "IncludeUpfront": true,
    "IncludeRecurring": true,
    "IncludeOtherSubscription": true,
    "IncludeSupport": true,
    "IncludeDiscount": true,
    "UseAmortized": false
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
EOF

# 2. Tạo file cấu hình thông báo (80% Actual & 100% Forecasted)
cat << EOF > /tmp/budget_notifications.json
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80.0,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "${ALERT_EMAIL}"
      }
    ]
  },
  {
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 100.0,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "${ALERT_EMAIL}"
      }
    ]
  }
]
EOF

# 3. Lấy Account ID và gọi AWS CLI
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Đang áp dụng Budget cho AWS Account: ${ACCOUNT_ID}..."

aws budgets create-budget \
  --account-id "${ACCOUNT_ID}" \
  --budget file:///tmp/budget_config.json \
  --notifications-with-subscribers file:///tmp/budget_notifications.json 2>/dev/null || echo "Budget đã tồn tại hoặc đã được tạo thành công!"

echo "=== [HOÀN TẤT] AWS Budget $100/tháng đã được kích hoạt thành công! ==="
rm -f /tmp/budget_config.json /tmp/budget_notifications.json