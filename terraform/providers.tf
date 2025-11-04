terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    ec = {
      source  = "elastic/ec"
      version = "~> 0.9.0"
    }
  }
}

# AWS Provider - Uses environment variables:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_REGION (optional, defaults to us-east-1)
provider "aws" {
  region = var.aws_region
}

# Elastic Cloud Provider - Uses environment variable:
# - EC_API_KEY
provider "ec" {
  # API key is automatically read from EC_API_KEY environment variable
}
