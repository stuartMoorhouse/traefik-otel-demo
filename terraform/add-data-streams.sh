#!/bin/bash
set -e

echo "========================================="
echo "Creating Elasticsearch Data Streams"
echo "========================================="

# Read environment variables from .env
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Verify required variables
if [ -z "$ELASTIC_ENDPOINT" ] || [ -z "$ELASTIC_API_KEY" ]; then
    echo "Error: ELASTIC_ENDPOINT and ELASTIC_API_KEY must be set in .env"
    exit 1
fi

echo "Using Elasticsearch endpoint: $ELASTIC_ENDPOINT"
echo ""

# Function to create component template
create_component_template() {
    local name=$1
    local settings=$2

    echo "Creating component template: ${name}..."

    curl -s -X PUT "${ELASTIC_ENDPOINT}/_component_template/${name}" \
        -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"template\": {
                \"settings\": ${settings}
            }
        }" | jq -r '.acknowledged // "Error"'
}

# Function to create index template
create_index_template() {
    local name=$1
    local pattern=$2
    local data_stream=$3
    local component_templates=$4

    echo "Creating index template: ${name}..."

    curl -s -X PUT "${ELASTIC_ENDPOINT}/_index_template/${name}" \
        -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"index_patterns\": [\"${pattern}\"],
            \"data_stream\": ${data_stream},
            \"composed_of\": ${component_templates},
            \"priority\": 500
        }" | jq -r '.acknowledged // "Error"'
}

# Function to create data stream
create_data_stream() {
    local name=$1

    echo "Creating data stream: ${name}..."

    curl -s -X PUT "${ELASTIC_ENDPOINT}/_data_stream/${name}" \
        -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
        -H "Content-Type: application/json" | jq -r '.acknowledged // "Error"'
}

echo "========================================="
echo "1. Creating Logs Data Stream (LogsDB)"
echo "========================================="

# Component template for LogsDB
create_component_template "logs-otel-demo-settings" '{
    "index": {
        "mode": "logsdb",
        "sort.field": ["@timestamp"],
        "sort.order": ["desc"]
    }
}'

# Index template for logs
create_index_template "logs-otel-demo" "logs-otel-demo" '{}' '["logs-otel-demo-settings"]'

# Create logs data stream
create_data_stream "logs-otel-demo"

echo "✓ Logs data stream created"
echo ""

echo "========================================="
echo "2. Creating Metrics Data Stream (TSDB)"
echo "========================================="

# Component template for TSDB
create_component_template "metrics-otel-demo-settings" '{
    "index": {
        "mode": "time_series",
        "routing_path": ["service.name", "host.name"],
        "sort.field": ["@timestamp"],
        "sort.order": ["desc"]
    }
}'

# Index template for metrics
create_index_template "metrics-otel-demo" "metrics-otel-demo" '{}' '["metrics-otel-demo-settings"]'

# Create metrics data stream
create_data_stream "metrics-otel-demo"

echo "✓ Metrics data stream created"
echo ""

echo "========================================="
echo "3. Creating Traces Data Stream"
echo "========================================="

# Component template for traces (standard data stream)
create_component_template "traces-otel-demo-settings" '{
    "index": {
        "sort.field": ["@timestamp"],
        "sort.order": ["desc"]
    }
}'

# Index template for traces
create_index_template "traces-otel-demo" "traces-otel-demo" '{}' '["traces-otel-demo-settings"]'

# Create traces data stream
create_data_stream "traces-otel-demo"

echo "✓ Traces data stream created"
echo ""

echo "========================================="
echo "Data Streams Created Successfully!"
echo "========================================="
echo ""

# Verify data streams
echo "Verifying data streams..."
echo ""

curl -s -X GET "${ELASTIC_ENDPOINT}/_data_stream/logs-otel-demo,metrics-otel-demo,traces-otel-demo" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "Content-Type: application/json" | jq -r '.data_streams[] | "- \(.name): \(.generation) generation(s)"'

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
