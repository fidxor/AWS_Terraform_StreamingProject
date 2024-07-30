variable "region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "ami_id" {
  description = "The ID of the AMI to use for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "The type of EC2 instance to launch"
  type        = string
  default     = "t2.micro"
}

variable "instance_name" {
  description = "The name tag for the EC2 instance"
  type        = string
  default     = "Admin-server"
}

variable "key_name" {
  description = "The name of the key pair to use for the EC2 instance"
  type        = string
}

variable "security_group_name" {
  description = "The name of the existing security group to use"
  type        = string
}