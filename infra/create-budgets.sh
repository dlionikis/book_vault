#!/usr/bin/env bash
set -euo pipefail

# Required: AWS_ACCOUNT_ID and ALERT_EMAIL environment variables
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${ALERT_EMAIL:?Set ALERT_EMAIL for budget notifications}"

REGION="us-east-1"

create_or_update_budget() {
  local name="$1"
  local budget_json="$2"
  local notifications_json="$3"

  if aws budgets describe-budget \
    --account-id "$AWS_ACCOUNT_ID" \
    --budget-name "$name" \
    --region "$REGION" &>/dev/null; then
    echo "Budget '$name' already exists, updating..."
    aws budgets update-budget \
      --account-id "$AWS_ACCOUNT_ID" \
      --new-budget "$budget_json" \
      --region "$REGION"
  else
    echo "Creating budget '$name'..."
    aws budgets create-budget \
      --account-id "$AWS_ACCOUNT_ID" \
      --budget "$budget_json" \
      --notifications-with-subscribers "$notifications_json" \
      --region "$REGION"
  fi
}

NOTIFICATIONS="[
  {
    \"Notification\": {
      \"NotificationType\": \"ACTUAL\",
      \"ComparisonOperator\": \"GREATER_THAN\",
      \"Threshold\": 80,
      \"ThresholdType\": \"PERCENTAGE\"
    },
    \"Subscribers\": [{
      \"SubscriptionType\": \"EMAIL\",
      \"Address\": \"$ALERT_EMAIL\"
    }]
  },
  {
    \"Notification\": {
      \"NotificationType\": \"FORECASTED\",
      \"ComparisonOperator\": \"GREATER_THAN\",
      \"Threshold\": 100,
      \"ThresholdType\": \"PERCENTAGE\"
    },
    \"Subscribers\": [{
      \"SubscriptionType\": \"EMAIL\",
      \"Address\": \"$ALERT_EMAIL\"
    }]
  }
]"

create_or_update_budget "BookVault-Monthly-Total" \
  '{
    "BudgetName": "BookVault-Monthly-Total",
    "BudgetLimit": { "Amount": "80", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  "$NOTIFICATIONS"

create_or_update_budget "BookVault-S3-Storage" \
  '{
    "BudgetName": "BookVault-S3-Storage",
    "BudgetLimit": { "Amount": "15", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "Service": ["Amazon Simple Storage Service"]
    }
  }' \
  "$NOTIFICATIONS"

echo "Budgets configured successfully."
