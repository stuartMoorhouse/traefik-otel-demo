# Traefik OTEL Demo with Elastic Cloud

A demonstration environment showing how Traefik and Prometheus data can be ingested via the EDOT (Elastic Distribution of OpenTelemetry) Collector into an Elastic Cloud instance.

## Project Overview

This project creates:
- An Elastic Cloud deployment for data storage and visualization
- An AWS EC2 instance running a Flask weather API with full observability instrumentation
- EDOT Collector to receive and forward telemetry data to Elastic Cloud
- Local Traefik reverse proxy with OpenTelemetry instrumentation
- Prometheus for metrics collection

## Architecture

```
                    ┌─→ Prometheus ──→ Prometheus UI (port 9090)
                    │
Flask Weather API ──┤
                    │
                    └─→ EDOT Collector ──→ Elastic Cloud
                                  ↑
                    ┌─────────────┤
                    │             │
Traefik ────────────┤             │
                    │             │
                    └─────────────┘
                                  ↑
                    ┌─────────────┤
                    │
Node Exporter ──────┤
  (System Metrics)  │
                    └─────────────┘
```

**Metrics Flow:**
- **Prometheus** scrapes metrics from Flask app, Traefik, and Node Exporter
  - Stores locally in TSDB for Prometheus UI access (port 9090)
  - Useful for debugging and ad-hoc PromQL queries
- **EDOT Collector** also scrapes the same targets independently
  - Applies resource processors to route to separate data streams
  - Sends all metrics to Elasticsearch with TSDB mode enabled
- **Node Exporter** provides system metrics (CPU, memory, disk, network, load)
- **Traces and Logs** from Flask go directly to EDOT via OTLP protocol

**Data Streams in Elasticsearch:**
- `metrics-traefik.otel-default` - Traefik proxy metrics (counters with TSDB)
- `metrics-flask.otel-default` - Flask application metrics
- `metrics-node.otel-default` - System/host metrics from Node Exporter
- `traces-apm.otel-default` - Distributed traces from Flask
- `logs-apm.otel-default` - Application logs from Flask

**Why both Prometheus and EDOT scrape?**
- EDOT (Elastic Distribution of OpenTelemetry) doesn't support Prometheus remote_write receiver
- Both scrape independently, providing redundancy and different use cases
- Prometheus UI excellent for quick debugging and PromQL exploration
- Elasticsearch provides long-term storage, ES|QL queries, and APM integration

## Prerequisites

1. **Elastic Cloud Account**
   - Free trial available at https://cloud.elastic.co/
   - Deployment with APM enabled

2. **AWS Account**
   - AWS account with EC2 permissions
   - SSH key pair created in your target region

3. **Local Tools**
   - Terraform >= 1.0
   - Docker and Docker Compose
   - AWS CLI (optional, for credential verification)

## Credential Setup

This project uses THREE different credential mechanisms. Understanding the difference is important:

### Credential Flow Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. ENVIRONMENT VARIABLES (export commands in your shell)           │
│    - AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY                       │
│    - EC_API_KEY                                                     │
│    Purpose: Terraform provider authentication                       │
│    Used by: Terraform to CREATE infrastructure                      │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 2. terraform.tfvars (configuration file in terraform/ directory)   │
│    - aws_region, key_name, instance_type                            │
│    - ec_region, deployment_name, elasticsearch_size                 │
│    Purpose: Infrastructure configuration (NOT credentials)          │
│    Used by: Terraform to CONFIGURE what gets created                │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
                    Terraform creates Elastic Cloud deployment
                    Terraform outputs: endpoints, tokens
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 3. .env (configuration file in project root)                       │
│    - ELASTIC_ENDPOINT (from Terraform output)                       │
│    - ELASTIC_APM_ENDPOINT (from Terraform output)                   │
│    - ELASTIC_APM_SECRET_TOKEN (from Terraform output)               │
│    - ELASTIC_API_KEY (from Terraform output or manually created)    │
│    Purpose: Runtime credentials for Docker services                 │
│    Used by: Docker Compose to RUN the application and EDOT Collector│
└─────────────────────────────────────────────────────────────────────┘
```

**Key Differences:**

1. **Environment Variables (Shell)**: Used by Terraform CLI to authenticate with AWS and Elastic Cloud APIs
2. **terraform.tfvars**: Used by Terraform to know WHAT to create (sizes, regions, names)
3. **.env**: Used by Docker at runtime to know WHERE to send data (endpoints from created infrastructure)

**Workflow:**
- Set environment variables → Run Terraform → Get outputs → Fill .env file → Run Docker Compose

---

This project uses environment variables for all sensitive credentials. Follow these steps carefully to ensure credentials are NEVER committed to source control.

### 1. AWS Credentials Setup

Set AWS credentials as environment variables (recommended):

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_REGION="us-east-1"  # Optional, defaults to us-east-1
```

**Alternative**: If you have AWS CLI configured, Terraform will automatically use `~/.aws/credentials`.

**Verify your credentials**:
```bash
aws sts get-caller-identity
```

### 2. Elastic Cloud Credentials Setup

#### Step 2.1: Get Elasticsearch Endpoint
1. Log into https://cloud.elastic.co/
2. Select your deployment (or create a new one)
3. Click "Copy endpoint" next to Elasticsearch
4. Format: `https://your-deployment-id.es.region.cloud.elastic.co:443`

#### Step 2.2: Get APM Endpoint and Secret Token
1. In your Elastic Cloud deployment, go to "Manage"
2. Click "Integrations" → "APM"
3. Copy the "Server URL" (APM endpoint)
4. Copy the "Secret token"

#### Step 2.3: Create API Key
1. Open Kibana from your deployment
2. Go to "Stack Management" → "API Keys"
3. Click "Create API Key"
4. Name: `traefik-otel-demo-ingest`
5. Permissions:
   ```json
   {
     "cluster": ["monitor"],
     "indices": [
       {
         "names": ["metrics-*", "traces-*", "logs-*"],
         "privileges": ["create_doc", "auto_configure", "create_index"]
       }
     ]
   }
   ```
6. Copy the Base64 encoded key (format: `id:api_key`)

#### Step 2.4: Set Elastic Cloud Environment Variables

```bash
export EC_API_KEY="your-elastic-cloud-api-key"
```

This is used by Terraform to create the Elastic Cloud deployment.

### 3. Create Terraform Variables File

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
# AWS Configuration
aws_region        = "us-east-1"
key_name          = "your-ssh-key-name"  # Your existing AWS SSH key
allowed_ssh_cidr  = "YOUR.IP.ADDRESS/32" # Your IP for security

# Elastic Cloud Configuration
ec_region       = "aws-us-east-1"
deployment_name = "traefik-otel-demo"
```

### 4. Create Docker Environment File

**IMPORTANT**: This file is populated AFTER you run Terraform (or if using existing Elastic Cloud).

```bash
cp .env.example .env
```

**Option A: After Terraform deployment** (recommended):
```bash
# Run Terraform first
cd terraform
terraform apply

# Get outputs
terraform output

# Copy the output values to .env file
cd ..
# Edit .env with values from terraform output
```

**Option B: Using existing Elastic Cloud deployment**:
Edit `.env` with values from Step 2 (manually obtained from Elastic Cloud console):

```bash
ELASTIC_ENDPOINT=https://your-deployment-id.es.us-east-1.aws.elastic-cloud.com:443
ELASTIC_APM_ENDPOINT=https://your-deployment-id.apm.us-east-1.aws.elastic-cloud.com:443
ELASTIC_APM_SECRET_TOKEN=your_apm_secret_token
ELASTIC_API_KEY=your_base64_encoded_api_key
```

## Security Checklist

Before proceeding, verify these files are in `.gitignore`:

- [x] `terraform/terraform.tfvars` - Contains AWS key names
- [x] `.env` - Contains all Elastic Cloud credentials
- [x] `state/` - Contains Terraform state with sensitive data
- [x] `.gitignore` itself - Per best practices

**Verify**:
```bash
git status
```

The files above should NOT appear in git status. If they do, DO NOT COMMIT. Check your `.gitignore`.

## Deployment

### Automated Deployment Flow

Terraform orchestrates the complete deployment in this order:

**Phase 1: Infrastructure Creation**
1. Creates Elastic Cloud deployment with Elasticsearch and Kibana
2. Creates AWS VPC, subnet, internet gateway, and security groups
3. Provisions EC2 instance with Docker and required tools

**Phase 2: Authentication Setup**
4. Generates Elasticsearch API key with appropriate permissions for OTEL data ingestion

**Phase 3: Data Stream Setup**
5. Creates three pre-configured data streams in Elasticsearch:
   - `logs-otel-demo` (LogsDB index mode)
   - `metrics-otel-demo` (TSDB index mode)
   - `traces-otel-demo` (standard data stream)

**Phase 4: Application Deployment**
6. Deploys Docker Compose stack with:
   - EDOT Collector (elastic/elastic-agent:9.2.0)
   - Flask Weather API with OpenTelemetry instrumentation
   - Traefik reverse proxy with OTEL tracing
   - Prometheus for metrics scraping

**Phase 5: Validation & Demo**
7. Tests connectivity to all services (Flask, Traefik, EDOT Collector)
8. Generates demo traffic with Traefik restarts to demonstrate Use Case 1 (counter reset handling)

### Run Deployment

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

The entire process takes ~10-15 minutes and is fully automated.

**After Deployment:**
```bash
terraform output  # View all endpoints and credentials
```

**Important: Timeout Handling**

Elastic Cloud deployments take 4-5 minutes. If Terraform times out during `ec_deployment` creation, wait 5 minutes then run `terraform refresh` followed by `terraform plan` to verify state before re-applying.

## What Gets Created

### Elasticsearch Data Streams
- `logs-otel-demo` - LogsDB for efficient log storage
- `metrics-otel-demo` - TSDB optimized for time-series data
- `traces-otel-demo` - Standard data stream for traces

### Services on EC2
Get the public IP from Terraform output, then access:
- Flask Weather API: `http://<ec2-ip>:5000`
- Traefik Dashboard: `http://<ec2-ip>:8080`
- Prometheus: `http://<ec2-ip>:9090`

### In Kibana
After deployment, open Kibana and navigate to:
- **Observability → APM → Services**: See "weather-api" and "traefik" services with traces
- **Discover**: Query `logs-otel-demo`, `metrics-otel-demo`, `traces-otel-demo` data streams
- **Metrics**: View counter reset demonstration data from Traefik restarts

## Use Case Demonstrations

### Use Case 1: Traefik Counter Reset Handling

**Requirement**: Calculate rate from Traefik failed request counter metrics without visual spikes when counters reset

**Problem**: Traefik exposes Prometheus counter metrics (like `traefik_entrypoint_requests_total`) that continuously increase over time. When Traefik restarts, these counters reset to 0. Traditional rate calculations create massive spikes or negative values at reset points, making graphs unusable.

**Solution**: Use ES|QL's `RATE()` function with TSDB counter data. The `RATE()` function automatically detects counter resets (when values decrease) and calculates rates correctly without spikes.

**ES|QL Query**:
```esql
// Query: Calculate rate of failed requests (4xx/5xx) from Traefik counters
//
// How it works:
// 1. TS command - Required for time-series data with counter types (enables RATE function)
// 2. Filter to failed requests (4xx/5xx status codes) in the last hour
// 3. RATE() - Calculates per-second rate and automatically handles counter resets
//    (when Traefik restarts and counter goes back to 0, RATE detects the reset
//     and calculates correctly without creating spikes)
// 4. AVG(RATE(...)) - Aggregates rate within each 5-minute time bucket
// 5. BUCKET(@timestamp, 5 minutes) - Groups data into 5-minute intervals for graphing
// 6. BY entrypoint - Creates separate series for each Traefik entrypoint (web, websecure, etc.)
// 7. Convert to requests per minute for easier interpretation
//
// Key insight: RATE() is counter-reset aware - it detects decreasing values
// and handles them correctly instead of showing massive negative spikes

TS metrics-traefik.otel-default
| WHERE traefik_entrypoint_requests_total IS NOT NULL
  AND @timestamp > NOW() - 1 hour
  AND (STARTS_WITH(code, "4") OR STARTS_WITH(code, "5"))
| STATS rate_per_sec = AVG(RATE(traefik_entrypoint_requests_total))
    BY BUCKET(@timestamp, 5 minutes), entrypoint
| EVAL rate_per_min = rate_per_sec * 60
| DROP rate_per_sec
```

**What is a counter?**
A Prometheus counter is a cumulative metric that only increases (100 → 150 → 200 → 250...) and only resets to 0 when the process restarts. Raw counter values aren't useful - you need the rate (change per unit time). The `RATE()` function calculates this derivative while handling resets.

---

### Use Case 2: Traefik Aggregated Rate Calculation

**Requirement**: Calculate and graph combined request rate across multiple Traefik entrypoints with high cardinality

**Problem**: When you have many Traefik entrypoints (web, websecure, traefik, etc.) each with their own counters, you cannot simply sum the counter values and then calculate rate. Why? Because different entrypoints may restart at different times, causing their counters to reset independently. Calculating rate from summed counters produces incorrect results.

**Solution**: Calculate rate for each individual time series first (handling each counter's resets independently), then sum the rates together. This is the fundamental principle: **rate-then-aggregate, not aggregate-then-rate**.

**ES|QL Query**:
```esql
// Query: Calculate total aggregated request rate across all Traefik entrypoints
//
// How it works:
// 1. Start with entrypoint-level counter metrics (traefik_entrypoint_requests_total)
// 2. Calculate RATE for each individual entrypoint/code/method combination
//    - This is critical: RATE must be calculated per time-series FIRST
//    - Each entrypoint can reset independently (separate containers, restarts, etc.)
//    - RATE handles each counter's resets separately
// 3. Convert individual rates to per-minute
// 4. SUM all individual rates together to get total request rate
//    - Now it's safe to aggregate because resets were handled at the per-series level
// 5. Group by time buckets to create a time-series graph showing total traffic
//
// Key insight: You MUST calculate rate on individual time series first, then aggregate.
// If you sum counters first and calculate rate after, you get wrong results when
// different entrypoints reset at different times (e.g., one restarts while others don't).
//
// Example of why order matters:
// - Entrypoint A: 100 → 150 → 200 (rate: 50/min, 50/min)
// - Entrypoint B: 500 → 550 → 0 → 50 (rate: 50/min, 50/min, 50/min - reset handled!)
// - Correct (rate then sum): 100/min, 100/min, 100/min
// - Wrong (sum then rate): 600 → 700 → 200 → massive spike at reset!

TS metrics-traefik.otel-default
| WHERE traefik_entrypoint_requests_total IS NOT NULL
  AND @timestamp > NOW() - 1 hour
| STATS rate_per_sec = AVG(RATE(traefik_entrypoint_requests_total))
    BY time_bucket = BUCKET(@timestamp, 5 minutes), entrypoint, code, method, protocol
| EVAL rate_per_min = rate_per_sec * 60
| STATS total_rate_per_min = SUM(rate_per_min) BY time_bucket
```

**Note on terminology**: "Entrypoint" in Traefik means the port/protocol where Traefik listens for incoming traffic (e.g., port 80 for HTTP, port 443 for HTTPS). This query aggregates across all entry points to show total traffic rate.

---

### Manually Generate More Traffic

To generate varied traffic patterns with counter resets for testing:

```bash
ssh -i <your-key>.pem ubuntu@<ec2-ip>
cd /home/ubuntu/traefik-otel-demo

# Generate traffic bursts with Traefik restart in the middle
for i in {1..5}; do
  curl -s http://localhost:5000/weather/london > /dev/null
  curl -s http://localhost:5000/weather/tokyo > /dev/null
  curl -s http://localhost:5000/nonexistent > /dev/null  # Generates 404s
done

# Restart Traefik to trigger counter reset
docker-compose restart traefik

# Continue generating traffic after restart
for i in {1..5}; do
  curl -s http://localhost:5000/weather/london > /dev/null
  curl -s http://localhost:5000/nonexistent > /dev/null
done
```

## Troubleshooting

### Credentials Not Working

**Problem**: "Authentication failed" in EDOT Collector logs

**Solution**:
1. Verify environment variables are set: `echo $EC_API_KEY`
2. Check `.env` file has correct values
3. Ensure API key has proper permissions
4. Verify endpoints don't have trailing slashes

### No Data in Elastic Cloud

**Problem**: Services running but no data appears in Kibana

**Solution**:
1. Check EDOT Collector debug output: `docker-compose logs edot-collector | grep -i error`
2. Verify APM endpoint and secret token are correct
3. Confirm API key has `ingest` privileges
4. Check network connectivity to Elastic Cloud

### Terraform State Issues

**Problem**: Terraform state is corrupted or lost

**Solution**:
1. State is in `state/` directory (not in git)
2. Backup before changes: `cp state/terraform.tfstate state/terraform.tfstate.backup`
3. If completely lost, you may need to import resources or recreate

## Cleanup

### Stop Docker Services
```bash
docker-compose down
```

### Remove Docker Volumes
```bash
docker-compose down -v
```

### Destroy Terraform Resources
```bash
cd terraform
terraform destroy
```

## Project Structure

```
.
├── README.md                       # This file
├── .gitignore                      # Prevents credential commits
├── .env.example                    # Template for Docker credentials
├── docker-compose.yml              # Local development services
├── app.py                          # Flask weather API
├── Dockerfile                      # Flask app container
├── edot-collector-config.yaml      # EDOT Collector configuration
├── prometheus.yml                  # Prometheus configuration
├── requirements.txt                # Python dependencies
├── state/                          # Terraform state (gitignored)
└── terraform/                      # Infrastructure as code
    ├── backend.tf                  # State configuration
    ├── providers.tf                # AWS and Elastic Cloud providers
    ├── variables.tf                # Variable definitions
    ├── terraform.tfvars.example    # Template for Terraform variables
    └── main.tf                     # Resource definitions (coming soon)
```

## Additional Resources

- [Elastic Observability Documentation](https://www.elastic.co/guide/en/observability/current/index.html)
- [EDOT Collector Documentation](https://www.elastic.co/guide/en/observability/current/elastic-distribution-opentelemetry.html)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)

## Security Notes

1. Never commit `.env` or `terraform.tfvars` files
2. Use IP allowlisting in `allowed_ssh_cidr` (not `0.0.0.0/0`)
3. Rotate API keys and tokens regularly
4. Use IAM roles instead of access keys when possible
5. Enable MFA on AWS and Elastic Cloud accounts
6. Review Elastic Cloud deployment security settings
