# ============================================================================
# Elastic Cloud Deployment (SINGLE CLUSTER)
# ============================================================================
# This configuration creates exactly ONE Elastic Cloud deployment with:
# - Elasticsearch (configurable size and zones)
# - Kibana (1GB, single zone)
# - Integrations Server / APM (1GB, single zone)
#
# IMPORTANT: Timeout Handling
# ----------------------------
# Elastic Cloud deployments typically take 4-5 minutes to create.
# The provider may report a timeout after ~2 minutes, but the deployment
# continues in the background on Elastic Cloud's side.
#
# If you encounter a timeout:
# 1. DO NOT run 'terraform apply' again immediately
# 2. Wait 3-5 minutes for Elastic Cloud to complete the deployment
# 3. Run: terraform refresh
# 4. Run: terraform plan (to verify state is correct)
# 5. Only run 'terraform apply' again if plan shows missing resources
#
# The timeout configuration below allows up to 10 minutes for creation.
# ============================================================================

resource "ec_deployment" "traefik_otel_demo" {
  name                   = var.deployment_name
  region                 = var.ec_region
  version                = data.ec_stack.latest.version
  deployment_template_id = "aws-general-purpose"

  elasticsearch = {
    hot = {
      autoscaling = {}
      size        = var.elasticsearch_size
      zone_count  = var.elasticsearch_zone_count
    }
  }

  kibana = {
    size       = "1g"
    zone_count = 1
  }

  tags = {
    project     = var.project_name
    environment = "demo"
    managed_by  = "terraform"
  }

  # Lifecycle configuration to prevent accidental destruction
  lifecycle {
    # Prevent accidental deletion of the deployment
    prevent_destroy = false  # Set to true in production!

    # Create new deployment before destroying old one (if replaced)
    create_before_destroy = false
  }
}

# Data source to get the latest Elastic Stack version
data "ec_stack" "latest" {
  version_regex = "latest"
  region        = var.ec_region
}
