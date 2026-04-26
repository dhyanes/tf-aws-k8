################################################################################
# Environment: dev
# Cost-optimised, minimal resources, single AZ
################################################################################

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  # Uncomment to use S3 remote state
  # backend "s3" {
  #   bucket = "my-tf-state"
  #   key    = "k8s/dev/terraform.tfstate"
  #   region = "ap-south-1"
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
  admin_cidr   = var.admin_cidr
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
  master_disk_size     = 20
  worker_disk_size     = 15
  encrypt_volumes      = false   # dev — skip encryption for speed

  tags = local.common_tags
}
