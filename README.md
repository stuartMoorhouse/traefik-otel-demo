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
Flask Weather API ──┐
                    ├─→ Prometheus ──(remote_write)──┐
Traefik ────────────┘         │                      │
                              │                      ├─→ EDOT Collector → Elastic Cloud
                              ↓                      │
                        Prometheus UI                │
                        (port 9090)                  │
                                                     │
Host Metrics ────────────────────────────────────────┘
```

**Metrics Flow:**
- Prometheus scrapes metrics from Flask app and Traefik
- Prometheus forwards all metrics to EDOT Collector via remote_write
- EDOT Collector also collects host metrics directly
- All metrics are sent to Elasticsearch for storage and visualization
- Prometheus UI remains available for troubleshooting and validation

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

### Use Case 1: Counter Reset Handling
The deployment automatically runs traffic generation with Traefik restarts. View results in Kibana:

**ES|QL Query to Handle Counter Resets:**
```sql
FROM metrics-otel-demo
| WHERE metric.name == "traefik_entrypoint_requests_total"
| EVAL rate_value = rate(metric.value)
| STATS request_rate = SUM(rate_value) BY bucket(@timestamp, 30 seconds)
```

The `rate()` function automatically detects and handles counter resets from Traefik restarts.

### Manually Generate More Traffic
SSH into the EC2 instance to run the traffic script again:
```bash
ssh -i <your-key>.pem ubuntu@<ec2-ip>
cd /home/ubuntu/traefik-otel-demo
./generate-traffic-with-restarts.sh
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
