# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# Data source to fetch existing security group
data "aws_security_group" "existing" {
  name = var.security_group_name
}

# Create an EC2 instance
resource "aws_instance" "admin_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  tags = {
    Name = var.instance_name
  }

  # Use the existing security group
  vpc_security_group_ids = [data.aws_security_group.existing.id]
}
