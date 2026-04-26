################################################################################
# Environment: prod
# Larger instances, encrypted volumes, locked-down admin CIDR
################################################################################

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  # Prod MUST use remote state with locking
  # backend "s3" {
  #   bucket         = "my-tf-state"
  #   key            = "k8s/prod/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "tf-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

locals {
  cluster_name = "k8s-${var.environment}"
  common_tags = {
    Project     = "k8s-cluster"
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = "platform"
  }
}

module "vpc" {
  source       = "../../modules/vpc"
  cluster_name = local.cluster_name
  vpc_cidr     = var.vpc_cidr
  subnet_cidr  = var.subnet_cidr
  tags         = local.common_tags
}

module "security_groups" {
  source       = "../../modules/security-groups"
  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  admin_cidr   = var.admin_cidr   # must be a specific IP/range in prod
  tags         = local.common_tags
}

module "iam" {
  source       = "../../modules/iam"
  cluster_name = local.cluster_name
  tags         = local.common_tags
}

module "compute" {
  source       = "../../modules/compute"
  cluster_name = local.cluster_name
  subnet_id    = module.vpc.subnet_id

  master_sg_id            = module.security_groups.master_sg_id
  worker_sg_id            = module.security_groups.worker_sg_id
  master_instance_profile = module.iam.master_instance_profile
  worker_instance_profile = module.iam.worker_instance_profile

  public_key_material  = var.public_key_material
  pod_network_cidr     = var.pod_network_cidr

  master_instance_type = var.master_instance_type
  worker_instance_type = var.worker_instance_type
  worker_count         = var.worker_count
  master_disk_size     = 50
  worker_disk_size     = 40
  encrypt_volumes      = true   # mandatory in prod

  tags = local.common_tags
}
