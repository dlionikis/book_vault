#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_NAME="BookVault"
DASHBOARD_BODY="$(cat "$SCRIPT_DIR/cloudwatch-dashboard.json")"

echo "Deploying CloudWatch dashboard: $DASHBOARD_NAME"

aws cloudwatch put-dashboard \
  --dashboard-name "$DASHBOARD_NAME" \
  --dashboard-body "$DASHBOARD_BODY" \
  --region us-east-1

echo "Dashboard deployed successfully."
echo "View at: https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=$DASHBOARD_NAME"
