################################################################################
# Kubernetes Cluster on AWS — 1 Master + 2 Worker Nodes
# Bootstrapped with kubeadm
################################################################################

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

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

################################################################################
# VPC & Networking
################################################################################

resource "aws_vpc" "k8s" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-vpc" })
}

resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id
  tags   = merge(local.common_tags, { Name = "${var.cluster_name}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-public-subnet" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.k8s.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id
  }

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Security Groups
################################################################################

# Master node security group
resource "aws_security_group" "master" {
  name        = "${var.cluster_name}-master-sg"
  description = "Security group for Kubernetes master node"
  vpc_id      = aws_vpc.k8s.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
    description = "SSH from admin"
  }

  # Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API Server"
  }

  # etcd server client API
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
    description = "etcd"
  }

  # Kubelet API (master)
  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
    description     = "Kubelet API"
  }

  # kube-scheduler
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
    description = "kube-scheduler"
  }

  # kube-controller-manager
  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
    description = "kube-controller-manager"
  }

  # Flannel VXLAN (CNI)
  ingress {
    from_port       = 8472
    to_port         = 8472
    protocol        = "udp"
    security_groups = [aws_security_group.worker.id]
    description     = "Flannel VXLAN"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-master-sg" })
}

# Worker node security group
resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.k8s.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
    description = "SSH from admin"
  }

  # Kubelet API
  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.master.id]
    description     = "Kubelet API from master"
  }

  # NodePort Services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort Services"
  }

  # Flannel VXLAN (CNI)
  ingress {
    from_port       = 8472
    to_port         = 8472
    protocol        = "udp"
    security_groups = [aws_security_group.master.id]
    description     = "Flannel VXLAN from master"
  }

  # Allow workers to communicate with each other
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Inter-worker communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-worker-sg" })
}

################################################################################
# IAM Role for Master (needed for cloud-provider integration)
################################################################################

resource "aws_iam_role" "master" {
  name = "${var.cluster_name}-master-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "master" {
  name = "${var.cluster_name}-master-policy"
  role = aws_iam_role.master.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:*", "elasticloadbalancing:*", "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer",
                    "ecr:GetRepositoryPolicy", "ecr:DescribeRepositories",
                    "ecr:ListImages", "ecr:BatchGetImage"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.cluster_name}-master-profile"
  role = aws_iam_role.master.name
}

resource "aws_iam_role" "worker" {
  name = "${var.cluster_name}-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.cluster_name}-worker-policy"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:Describe*", "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer",
                    "ecr:GetRepositoryPolicy", "ecr:DescribeRepositories",
                    "ecr:ListImages", "ecr:BatchGetImage"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_name}-worker-profile"
  role = aws_iam_role.worker.name
}

################################################################################
# Key Pair
################################################################################

resource "aws_key_pair" "k8s" {
  key_name   = "${var.cluster_name}-key"
  public_key = var.public_key_material

  tags = local.common_tags
}

################################################################################
# EC2 Instances
################################################################################

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.k8s.key_name
  vpc_security_group_ids = [aws_security_group.master.id]
  iam_instance_profile   = aws_iam_instance_profile.master.name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/scripts/master.sh", {
    pod_cidr     = var.pod_network_cidr
    cluster_name = var.cluster_name
  }))

  tags = merge(local.common_tags, {
    Name                                        = "${var.cluster_name}-master"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "master"
  })
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.k8s.key_name
  vpc_security_group_ids = [aws_security_group.worker.id]
  iam_instance_profile   = aws_iam_instance_profile.worker.name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/scripts/worker.sh", {
    master_private_ip = aws_instance.master.private_ip
    cluster_name      = var.cluster_name
  }))

  tags = merge(local.common_tags, {
    Name                                        = "${var.cluster_name}-worker-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                        = "worker"
  })

  depends_on = [aws_instance.master]
}

################################################################################
# Locals
################################################################################

locals {
  common_tags = {
    Project     = var.cluster_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
