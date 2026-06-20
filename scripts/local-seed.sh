#!/usr/bin/env bash
# Seed LocalStack with secrets that the services read via AWS Secrets Manager SDK.
# Run AFTER `docker compose -f docker-compose.local.yml up -d` and LocalStack is healthy.
# Usage: ./scripts/local-seed.sh

set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

AWS="aws --endpoint-url ${ENDPOINT} --region ${REGION} --no-cli-pager"

echo "==> Checking LocalStack health..."
curl -sf "${ENDPOINT}/_localstack/health" | grep -q '"secretsmanager"' || {
  echo "ERROR: LocalStack not ready or secretsmanager not available"
  exit 1
}

echo "==> Seeding Secrets Manager..."

# Load from .env.local if it exists (never committed)
if [ -f "$(dirname "$0")/../.env.local" ]; then
  set -a; source "$(dirname "$0")/../.env.local"; set +a
fi

JWT_SECRET="${JWT_SECRET:-local-dev-secret-change-me}"
DB_URL="postgres://demo:demo@postgres:5432/demo"
CLUSTER="demo-local"

# Create or update secrets (idempotent)
for SECRET_NAME in "/${CLUSTER}/jwt-secret" "/${CLUSTER}/db-url"; do
  if $AWS secretsmanager describe-secret --secret-id "${SECRET_NAME}" >/dev/null 2>&1; then
    echo "  update ${SECRET_NAME}"
    if [ "${SECRET_NAME}" = "/${CLUSTER}/jwt-secret" ]; then
      $AWS secretsmanager update-secret --secret-id "${SECRET_NAME}" --secret-string "${JWT_SECRET}"
    else
      $AWS secretsmanager update-secret --secret-id "${SECRET_NAME}" --secret-string "${DB_URL}"
    fi
  else
    echo "  create ${SECRET_NAME}"
    if [ "${SECRET_NAME}" = "/${CLUSTER}/jwt-secret" ]; then
      $AWS secretsmanager create-secret --name "${SECRET_NAME}" --secret-string "${JWT_SECRET}"
    else
      $AWS secretsmanager create-secret --name "${SECRET_NAME}" --secret-string "${DB_URL}"
    fi
  fi
done

# Write alertmanager webhook token file so alertmanager can read it
WEBHOOK_TOKEN="${ANVAY_WEBHOOK_TOKEN:-}"
WEBHOOK_FILE="$(dirname "$0")/../local/alertmanager/webhook-token"
if [ -n "$WEBHOOK_TOKEN" ]; then
  echo -n "$WEBHOOK_TOKEN" > "$WEBHOOK_FILE"
  echo "==> Wrote alertmanager webhook-token file"
else
  echo "WARNING: ANVAY_WEBHOOK_TOKEN not set — alertmanager will fail to auth with Anvay"
  echo -n "anvay-demo-webhook-token" > "$WEBHOOK_FILE"
  echo "  Using default dev token: anvay-demo-webhook-token"
  echo "  Set ANVAY_WEBHOOK_TOKEN=anvay-demo-webhook-token in apps/gateway/.env too"
fi

echo ""
echo "==> LocalStack secrets seeded."
echo "    Secrets Manager endpoint: ${ENDPOINT}"
echo ""
echo "    To verify:"
echo "      aws --endpoint-url ${ENDPOINT} secretsmanager list-secrets --region ${REGION}"
