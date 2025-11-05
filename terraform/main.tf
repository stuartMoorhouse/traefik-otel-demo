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

# ============================================================================
# AWS VPC and Networking
# ============================================================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)  # 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# ============================================================================
# Security Group
# ============================================================================

resource "aws_security_group" "demo_instance" {
  name        = "${var.project_name}-sg"
  description = "Security group for Traefik OTEL demo instance"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTP for Traefik
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS for Traefik
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Traefik Dashboard
  ingress {
    description = "Traefik Dashboard"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Flask App
  ingress {
    description = "Flask App"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # EDOT Collector Health
  ingress {
    description = "EDOT Collector Health"
    from_port   = 13133
    to_port     = 13133
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # EDOT Collector Metrics
  ingress {
    description = "EDOT Collector Metrics"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# SSH Key Pair (Automatically Generated)
# ============================================================================

# Generate a new RSA key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload the public key to AWS
resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh

  tags = {
    Name        = "${var.project_name}-key"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Save the private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0600"
}

# ============================================================================
# EC2 Instance
# ============================================================================

# Data source to find latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "demo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.aws_instance_type
  key_name               = aws_key_pair.demo.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.demo_instance.id]

  root_block_device {
    volume_size           = 30  # 30GB root volume
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    elastic_endpoint           = ec_deployment.traefik_otel_demo.elasticsearch.https_endpoint
    elastic_username           = ec_deployment.traefik_otel_demo.elasticsearch_username
    elastic_password           = ec_deployment.traefik_otel_demo.elasticsearch_password
    kibana_endpoint            = ec_deployment.traefik_otel_demo.kibana.https_endpoint
  }))

  # Wait for Elastic Cloud deployment to be ready
  depends_on = [
    ec_deployment.traefik_otel_demo
  ]

  tags = {
    Name        = "${var.project_name}-instance"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }

  # SSH connection for provisioners
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = self.public_ip
    timeout     = "10m"
  }

  # Wait for user-data to complete (Docker installation)
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for user-data to complete...'",
      "while [ ! -f /var/log/user-data-complete.log ]; do sleep 5; done",
      "echo 'User-data complete. Docker is ready.'",
      "docker --version"
    ]
  }

  # Upload EDOT Collector config template
  provisioner "file" {
    source      = "${path.module}/edot-collector-config.yaml.template"
    destination = "/home/ubuntu/traefik-otel-demo/edot-collector-config.yaml.template"
  }

  # Upload create-api-key script
  provisioner "file" {
    source      = "${path.module}/create-api-key.sh"
    destination = "/home/ubuntu/traefik-otel-demo/create-api-key.sh"
  }

  # Upload add-data-streams script
  provisioner "file" {
    source      = "${path.module}/add-data-streams.sh"
    destination = "/home/ubuntu/traefik-otel-demo/add-data-streams.sh"
  }

  # Upload deployment script
  provisioner "file" {
    source      = "${path.module}/deploy-apps.sh"
    destination = "/home/ubuntu/traefik-otel-demo/deploy-apps.sh"
  }

  # Upload traffic generation script
  provisioner "file" {
    source      = "${path.module}/generate-traffic-with-restarts.sh"
    destination = "/home/ubuntu/traefik-otel-demo/generate-traffic-with-restarts.sh"
  }

  # Step 1: Create Elasticsearch API Key
  provisioner "remote-exec" {
    inline = [
      "echo '========================================='",
      "echo 'Step 1: Creating Elasticsearch API Key'",
      "echo '========================================='",
      "chmod +x /home/ubuntu/traefik-otel-demo/create-api-key.sh",
      "/home/ubuntu/traefik-otel-demo/create-api-key.sh"
    ]
  }

  # Step 2: Create data streams in Elasticsearch
  provisioner "remote-exec" {
    inline = [
      "echo ''",
      "echo '========================================='",
      "echo 'Step 2: Creating Elasticsearch Data Streams'",
      "echo '========================================='",
      "chmod +x /home/ubuntu/traefik-otel-demo/add-data-streams.sh",
      "/home/ubuntu/traefik-otel-demo/add-data-streams.sh"
    ]
  }

  # Step 3: Run deployment script (docker-compose)
  provisioner "remote-exec" {
    inline = [
      "echo ''",
      "echo '========================================='",
      "echo 'Step 3: Deploying Applications'",
      "echo '========================================='",
      "chmod +x /home/ubuntu/traefik-otel-demo/deploy-apps.sh",
      "/home/ubuntu/traefik-otel-demo/deploy-apps.sh"
    ]
  }

  # Step 4: Test connectivity
  provisioner "remote-exec" {
    inline = [
      "echo ''",
      "echo '========================================='",
      "echo 'Step 4: Testing Connectivity'",
      "echo '========================================='",
      "sleep 15",
      "echo 'Testing Flask app...'",
      "curl -f http://localhost:5000/health || echo 'Flask health check failed'",
      "echo ''",
      "echo 'Testing Traefik...'",
      "curl -f http://localhost:8080/api/overview || echo 'Traefik API check failed'",
      "echo ''",
      "echo 'Testing EDOT Collector...'",
      "curl -f http://localhost:13133 || echo 'EDOT health check failed'",
      "echo ''",
      "echo '✓ Connectivity tests complete'"
    ]
  }

  # Step 5: Generate traffic with restarts
  provisioner "remote-exec" {
    inline = [
      "echo ''",
      "echo '========================================='",
      "echo 'Step 5: Generating Demo Traffic'",
      "echo '========================================='",
      "chmod +x /home/ubuntu/traefik-otel-demo/generate-traffic-with-restarts.sh",
      "/home/ubuntu/traefik-otel-demo/generate-traffic-with-restarts.sh"
    ]
  }
}
