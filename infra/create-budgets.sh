#!/usr/bin/env bash
set -euo pipefail

# Required: AWS_ACCOUNT_ID and ALERT_EMAIL environment variables
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${ALERT_EMAIL:?Set ALERT_EMAIL for budget notifications}"

REGION="us-east-1"

echo "Creating $80/month total budget..."
aws budgets create-budget \
  --account-id "$AWS_ACCOUNT_ID" \
  --budget '{
    "BudgetName": "BookVault-Monthly-Total",
    "BudgetLimit": { "Amount": "80", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers "[
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
  ]" \
  --region "$REGION"

echo "Creating $15/month S3 sub-budget..."
aws budgets create-budget \
  --account-id "$AWS_ACCOUNT_ID" \
  --budget '{
    "BudgetName": "BookVault-S3-Storage",
    "BudgetLimit": { "Amount": "15", "Unit": "USD" },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "Service": ["Amazon Simple Storage Service"]
    }
  }' \
  --notifications-with-subscribers "[
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
  ]" \
  --region "$REGION"

echo "Budgets created successfully."
