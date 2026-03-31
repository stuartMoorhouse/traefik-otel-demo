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
    prevent_destroy = false # Set to true in production!

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
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Detect the operator's public IP for security group rules
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

# Ubuntu 22.04 LTS AMI
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

# fck-nat AMI (ARM64, AL2023)
data "aws_ami" "fck_nat" {
  most_recent = true
  owners      = ["568608671756"]

  filter {
    name   = "name"
    values = ["fck-nat-al2023-*-arm64-ebs"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

locals {
  my_ip_cidr          = "${chomp(data.http.my_ip.response_body)}/32"
  allowed_cidr        = var.allowed_cidr != "" ? var.allowed_cidr : local.my_ip_cidr
  private_subnet_cidr = cidrsubnet(var.vpc_cidr, 8, 2)
}

# ============================================================================
# VPC and Networking
# ============================================================================

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

# Public Subnet 1 (AZ[0])
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1) # 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Public Subnet 2 (AZ[1]) — required for ALB
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 3) # 10.0.3.0/24
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Private Subnet (AZ[0])
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidr # 10.0.2.0/24
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Public Route Table
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

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table (routes through fck-nat)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.fck_nat.primary_network_interface_id
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ============================================================================
# fck-nat Instance
# ============================================================================

resource "aws_instance" "fck_nat" {
  ami                         = data.aws_ami.fck_nat.id
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.fck_nat.id]
  associate_public_ip_address = true # nosemgrep: terraform.aws.security.aws-ec2-has-public-ip.aws-ec2-has-public-ip — NAT instance requires public IP
  source_dest_check           = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name        = "${var.project_name}-fck-nat"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# Security Groups
# ============================================================================

# --- EC2 Security Group ---
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instance in private subnet"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from ALB on service ports
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Flask from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Traefik Dashboard from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Prometheus from ALB"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "EDOT Collector Health from ALB"
    from_port       = 13133
    to_port         = 13133
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "EDOT Collector Metrics from ALB"
    from_port       = 8888
    to_port         = 8888
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Egress: HTTPS to internet (via NAT)
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: HTTP to internet (via NAT)
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: DNS to VPC CIDR only
  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "${var.project_name}-ec2-sg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# --- ALB Security Group ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # Ingress from operator IP on service ports
  ingress {
    description = "HTTP from operator"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.allowed_cidr]
  }

  ingress {
    description = "Traefik Dashboard from operator"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.allowed_cidr]
  }

  ingress {
    description = "Prometheus from operator"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [local.allowed_cidr]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ALB egress to EC2 SG on service ports
resource "aws_security_group_rule" "alb_to_ec2_flask" {
  description              = "Flask app from ALB"
  type                     = "egress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "alb_to_ec2_traefik" {
  description              = "Traefik dashboard from ALB"
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "alb_to_ec2_prometheus" {
  description              = "Prometheus from ALB"
  type                     = "egress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.ec2.id
}

# --- VPC Endpoint Security Group ---
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project_name}-vpce-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.private_subnet_cidr]
  }

  tags = {
    Name        = "${var.project_name}-vpce-sg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# --- fck-nat Security Group ---
resource "aws_security_group" "fck_nat" {
  name        = "${var.project_name}-fck-nat-sg"
  description = "Security group for fck-nat instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.private_subnet_cidr]
  }

  ingress {
    description = "HTTP from private subnet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.private_subnet_cidr]
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-fck-nat-sg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# Application Load Balancer
# ============================================================================

# nosemgrep: terraform.aws.security.aws-elb-access-logs-not-enabled.aws-elb-access-logs-not-enabled — demo environment, no S3 bucket for logs
resource "aws_lb" "main" {
  name                       = "${var.project_name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = [aws_subnet.public.id, aws_subnet.public_2.id]
  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = {
    Name        = "${var.project_name}-alb"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# --- Target Groups ---

resource "aws_lb_target_group" "flask" {
  name     = "${var.project_name}-flask-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    port                = "5000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name        = "${var.project_name}-flask-tg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_lb_target_group" "traefik" {
  name     = "${var.project_name}-traefik-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/api/overview"
    port                = "8080"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name        = "${var.project_name}-traefik-tg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_lb_target_group" "prometheus" {
  name     = "${var.project_name}-prom-tg"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/-/healthy"
    port                = "9090"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name        = "${var.project_name}-prom-tg"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# --- Target Group Attachments ---

resource "aws_lb_target_group_attachment" "flask" {
  target_group_arn = aws_lb_target_group.flask.arn
  target_id        = aws_instance.demo.id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "traefik" {
  target_group_arn = aws_lb_target_group.traefik.arn
  target_id        = aws_instance.demo.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "prometheus" {
  target_group_arn = aws_lb_target_group.prometheus.arn
  target_id        = aws_instance.demo.id
  port             = 9090
}

# --- Listeners ---

# nosemgrep: terraform.aws.security.insecure-load-balancer-tls-version.insecure-load-balancer-tls-version — demo environment, no domain/cert for HTTPS
resource "aws_lb_listener" "flask" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask.arn
  }

  tags = {
    Name        = "${var.project_name}-flask-listener"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# nosemgrep: terraform.aws.security.insecure-load-balancer-tls-version.insecure-load-balancer-tls-version
resource "aws_lb_listener" "traefik" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }

  tags = {
    Name        = "${var.project_name}-traefik-listener"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# nosemgrep: terraform.aws.security.insecure-load-balancer-tls-version.insecure-load-balancer-tls-version
resource "aws_lb_listener" "prometheus" {
  load_balancer_arn = aws_lb.main.arn
  port              = 9090
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus.arn
  }

  tags = {
    Name        = "${var.project_name}-prometheus-listener"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# VPC Endpoints (SSM + S3)
# ============================================================================

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVPCAccess"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "ssm:*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceVpc" = aws_vpc.main.id } }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ssm-vpce"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVPCAccess"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "ssmmessages:*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceVpc" = aws_vpc.main.id } }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ssmmessages-vpce"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVPCAccess"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "ec2messages:*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceVpc" = aws_vpc.main.id } }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ec2messages-vpce"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVPCAccess"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "s3:*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceVpc" = aws_vpc.main.id } }
    }]
  })

  tags = {
    Name        = "${var.project_name}-s3-vpce"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Elastic Cloud PrivateLink (conditional)
resource "aws_vpc_endpoint" "elastic_cloud" {
  count = var.elastic_cloud_vpce_service_name != "" ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = var.elastic_cloud_vpce_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVPCAccess"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceVpc" = aws_vpc.main.id } }
    }]
  })

  tags = {
    Name        = "${var.project_name}-elastic-cloud-vpce"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# Elastic Cloud Traffic Filter (conditional — PrivateLink)
# ============================================================================

resource "ec_deployment_traffic_filter" "vpce" {
  count = var.elastic_cloud_vpce_service_name != "" ? 1 : 0

  name   = "${var.project_name}-vpce-filter"
  region = var.ec_region
  type   = "vpce"

  rule {
    source = aws_vpc_endpoint.elastic_cloud[0].id
  }
}

resource "ec_deployment_traffic_filter_association" "vpce" {
  count = var.elastic_cloud_vpce_service_name != "" ? 1 : 0

  traffic_filter_id = ec_deployment_traffic_filter.vpce[0].id
  deployment_id     = ec_deployment.traefik_otel_demo.id
}

# ============================================================================
# IAM Role for SSM
# ============================================================================

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-ssm-role"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = {
    Name        = "${var.project_name}-ec2-ssm-profile"
    Project     = var.project_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# EC2 Instance
# ============================================================================

resource "aws_instance" "demo" {
  ami                     = data.aws_ami.ubuntu.id
  instance_type           = var.aws_instance_type
  subnet_id               = aws_subnet.private.id
  vpc_security_group_ids  = [aws_security_group.ec2.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_ssm.name
  disable_api_termination = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 30 # 30GB root volume
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    elastic_endpoint = ec_deployment.traefik_otel_demo.elasticsearch.https_endpoint
    elastic_username = ec_deployment.traefik_otel_demo.elasticsearch_username
    elastic_password = ec_deployment.traefik_otel_demo.elasticsearch_password
    kibana_endpoint  = ec_deployment.traefik_otel_demo.kibana.https_endpoint
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
}
