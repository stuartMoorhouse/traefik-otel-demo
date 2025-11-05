#!/bin/bash
set -e

echo "========================================="
echo "Creating Elasticsearch API Key"
echo "========================================="

PROJECT_DIR="/home/ubuntu/traefik-otel-demo"
cd $PROJECT_DIR

# Read environment variables from .env
source .env

# Verify required variables
if [ -z "$ELASTIC_ENDPOINT" ] || [ -z "$ELASTIC_USERNAME" ] || [ -z "$ELASTIC_PASSWORD" ]; then
    echo "Error: ELASTIC_ENDPOINT, ELASTIC_USERNAME, and ELASTIC_PASSWORD must be set in .env"
    exit 1
fi

echo "Using Elasticsearch endpoint: $ELASTIC_ENDPOINT"
echo ""

# Check if API key already exists and is valid
if [ "$ELASTIC_API_KEY" != "PLACEHOLDER" ] && [ -n "$ELASTIC_API_KEY" ]; then
    echo "API key already exists in .env, testing validity..."

    # Test if the existing API key works
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
        "${ELASTIC_ENDPOINT}/_cluster/health")

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Existing API key is valid, skipping creation"
        exit 0
    else
        echo "⚠ Existing API key is invalid (HTTP $HTTP_CODE), generating new one..."
    fi
fi

# Generate new API key
echo "Generating new API key..."

API_KEY_RESPONSE=$(curl -s -X POST "${ELASTIC_ENDPOINT}/_security/api_key" \
  -u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "traefik-otel-demo-auto",
    "role_descriptors": {
      "otel_writer": {
        "cluster": ["monitor", "manage_index_templates"],
        "indices": [
          {
            "names": ["metrics-*", "traces-*", "logs-*"],
            "privileges": ["create_doc", "auto_configure", "create_index", "write"]
          }
        ]
      }
    }
  }')

# Extract API key from response
API_KEY=$(echo $API_KEY_RESPONSE | jq -r '.encoded')

if [ "$API_KEY" != "null" ] && [ -n "$API_KEY" ]; then
  echo "✓ Successfully generated API key"
  # Update .env file with real API key
  sed -i "s/ELASTIC_API_KEY=PLACEHOLDER/ELASTIC_API_KEY=$API_KEY/" .env
  echo "✓ Updated .env file with new API key"
else
  echo "✗ Error: Could not generate API key"
  echo "Response: $API_KEY_RESPONSE"
  exit 1
fi

echo ""
echo "========================================="
echo "API Key Creation Complete!"
echo "========================================="
