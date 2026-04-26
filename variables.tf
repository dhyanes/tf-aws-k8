################################################################################
# Variables
################################################################################

variable "aws_region" {
  description = "AWS region to deploy the cluster"
  type        = string
  default     = "ap-south-1" # Mumbai — closest to Tiruppur, TN
}

variable "cluster_name" {
  description = "Name prefix for all cluster resources"
  type        = string
  default     = "k8s-cluster"
}

variable "environment" {
  description = "Environment tag (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "pod_network_cidr" {
  description = "CIDR block for Kubernetes pod network (Flannel default)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "master_instance_type" {
  description = "EC2 instance type for the master node"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GB RAM — kubeadm minimum
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "public_key_material" {
  description = "SSH public key content (e.g. contents of ~/.ssh/id_rsa.pub)"
  type        = string
  sensitive   = true
}

variable "admin_cidr" {
  description = "Your IP CIDR for SSH access (e.g. 203.0.113.10/32). Use 0.0.0.0/0 only for testing."
  type        = string
  default     = "0.0.0.0/0"
}
