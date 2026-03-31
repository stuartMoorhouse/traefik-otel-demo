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

# Summary output for easy .env file creation
output "env_file_template" {
  description = "Template for .env file (fill in ELASTIC_API_KEY manually)"
  value       = <<-EOT
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
  sensitive   = true
}

# ============================================================================
# EC2 / Infrastructure Outputs
# ============================================================================

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.demo.id
}

output "ec2_private_ip" {
  description = "EC2 instance private IP address"
  value       = aws_instance.demo.private_ip
}

output "ssm_connect_command" {
  description = "AWS SSM command to connect to the instance"
  value       = "aws ssm start-session --target ${aws_instance.demo.id} --region ${var.aws_region}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

# ============================================================================
# Service URLs (via ALB)
# ============================================================================

output "flask_app_url" {
  description = "Flask Application URL (via ALB port 80)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "traefik_dashboard_url" {
  description = "Traefik Dashboard URL (via ALB port 8080)"
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "prometheus_url" {
  description = "Prometheus URL (via ALB port 9090)"
  value       = "http://${aws_lb.main.dns_name}:9090"
}

# Instructions for next steps
output "next_steps" {
  description = "Instructions for completing the setup"
  value       = <<-EOT

  ========================================
  Elastic Cloud Deployment Created!
  ========================================

  Deployment ID: ${ec_deployment.traefik_otel_demo.id}

  IMPORTANT NEXT STEPS:

  1. Connect to the EC2 instance via SSM:
     aws ssm start-session --target ${aws_instance.demo.id} --region ${var.aws_region}

  2. Access services via ALB:
     Flask App:          http://${aws_lb.main.dns_name}
     Traefik Dashboard:  http://${aws_lb.main.dns_name}:8080
     Prometheus:         http://${aws_lb.main.dns_name}:9090

  3. View Elastic Cloud credentials:
     terraform output -raw elasticsearch_password

  4. Open Kibana:
     ${ec_deployment.traefik_otel_demo.kibana.https_endpoint}

  ========================================
  EOT
}
