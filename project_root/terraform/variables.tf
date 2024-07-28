# variables.tf

variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the private SSH key for EC2 instances"
  type        = string
  default     = "~/monitoring_new.pem"
}

variable "key_name" {
  description = "The key pair name for EC2 instances"
  type        = string
}

variable "cluster_name" {
  description = "The name of the Kubernetes cluster"
  type        = string
}

variable "instance_type_main" {
  description = "Instance type for the main monitoring node"
  type        = string
}

variable "instance_type_worker" {
  description = "Instance type for worker nodes"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}