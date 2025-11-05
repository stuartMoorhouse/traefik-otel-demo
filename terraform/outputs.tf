# Deployment Information
output "deployment_id" {
  description = "Elastic Cloud deployment ID"
  value       = ec_deployment.traefik_otel_demo.id
}

output "deployment_name" {
  description = "Elastic Cloud deployment name"
  value       = ec_deployment.traefik_otel_demo.name
}

output "elasticsearch_version" {
  description = "Elasticsearch version deployed"
  value       = ec_deployment.traefik_otel_demo.version
}

# Elasticsearch Endpoints
output "elasticsearch_endpoint" {
  description = "Elasticsearch HTTPS endpoint (for ELASTIC_ENDPOINT in .env)"
  value       = ec_deployment.traefik_otel_demo.elasticsearch.https_endpoint
}

output "elasticsearch_cloud_id" {
  description = "Elasticsearch Cloud ID"
  value       = ec_deployment.traefik_otel_demo.elasticsearch.cloud_id
  sensitive   = true
}

# Elasticsearch Credentials
output "elasticsearch_username" {
  description = "Elasticsearch username (elastic)"
  value       = ec_deployment.traefik_otel_demo.elasticsearch_username
  sensitive   = true
}

output "elasticsearch_password" {
  description = "Elasticsearch password (use to create API keys)"
  value       = ec_deployment.traefik_otel_demo.elasticsearch_password
  sensitive   = true
}

# Kibana Endpoint
output "kibana_endpoint" {
  description = "Kibana HTTPS endpoint"
  value       = ec_deployment.traefik_otel_demo.kibana.https_endpoint
}

# Instructions for next steps
output "next_steps" {
  description = "Instructions for completing the setup"
  value = <<-EOT

  ========================================
  Elastic Cloud Deployment Created!
  ========================================

  Deployment ID: ${ec_deployment.traefik_otel_demo.id}

  IMPORTANT NEXT STEPS:

  1. View all outputs (including sensitive values):
     terraform output

  2. View sensitive values individually:
     terraform output -raw elasticsearch_password

  3. Create an API key for OTel data ingestion:
     - Open Kibana: ${ec_deployment.traefik_otel_demo.kibana.https_endpoint}
     - Login with username 'elastic' and password from: terraform output -raw elasticsearch_password
     - Go to: Stack Management → Security → API Keys
     - Create API Key with name: traefik-otel-demo-ingest
     - Grant privileges:
       * Cluster: monitor
       * Index privileges on metrics-*, traces-*, logs-*: create_doc, auto_configure, create_index
     - Copy the Base64 encoded key

  4. Create your .env file:
     cd ..
     cp .env.example .env

  5. Edit .env with the Elasticsearch endpoint and API key:
     ELASTIC_ENDPOINT=${ec_deployment.traefik_otel_demo.elasticsearch.https_endpoint}
     ELASTIC_API_KEY=<created in step 3>

  6. Start the demo application:
     docker-compose up -d

  ========================================
  EOT
}

# Summary output for easy .env file creation
output "env_file_template" {
  description = "Template for .env file (fill in ELASTIC_API_KEY manually)"
  value = <<-EOT
# Copy these values to your .env file
# OTel data will be sent directly to Elasticsearch (no APM server needed)
ELASTIC_ENDPOINT=${ec_deployment.traefik_otel_demo.elasticsearch.https_endpoint}
ELASTIC_API_KEY=<CREATE_THIS_IN_KIBANA>

# To create the API key:
# 1. Login to Kibana: ${ec_deployment.traefik_otel_demo.kibana.https_endpoint}
# 2. Username: elastic
# 3. Password: Run 'terraform output -raw elasticsearch_password'
# 4. Go to Stack Management → Security → API Keys → Create API Key
# 5. Grant cluster privilege 'monitor' and index privileges on metrics-*/traces-*/logs-*
  EOT
  sensitive = true
}

# ============================================================================
# EC2 Instance Outputs
# ============================================================================

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "ec2_public_ip" {
  description = "EC2 instance public IP address"
  value       = aws_instance.demo.public_ip
}

output "ec2_public_dns" {
  description = "EC2 instance public DNS name"
  value       = aws_instance.demo.public_dns
}

output "ec2_private_key_path" {
  description = "Path to the generated private SSH key"
  value       = local_file.private_key.filename
}

output "ec2_ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.demo.public_ip}"
}

# ============================================================================
# Service URLs
# ============================================================================

output "traefik_dashboard_url" {
  description = "Traefik Dashboard URL"
  value       = "http://${aws_instance.demo.public_ip}:8080"
}

output "flask_app_url" {
  description = "Flask Application URL"
  value       = "http://${aws_instance.demo.public_ip}:5000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${aws_instance.demo.public_ip}:9090"
}
