# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  description = "EC2 instance type for the monitoring VM"
  type        = string
  default     = "t3.large"  # 2 vCPUs, 8GB RAM
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "traefik-otel-demo"
}

# Elastic Cloud Configuration
variable "ec_region" {
  description = "Elastic Cloud region (e.g., aws-us-east-1, gcp-us-central1)"
  type        = string
  default     = "aws-us-east-1"
}

variable "deployment_name" {
  description = "Name of the Elastic Cloud deployment"
  type        = string
  default     = "traefik-otel-demo"
}

variable "elasticsearch_size" {
  description = "Size of Elasticsearch nodes in GB"
  type        = string
  default     = "1g"
}

variable "elasticsearch_zone_count" {
  description = "Number of availability zones for Elasticsearch"
  type        = number
  default     = 1
}

# Networking
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the EC2 instance"
  type        = string
  default     = "0.0.0.0/0"  # Restrict this in production!
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}
