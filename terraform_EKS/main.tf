# Configure the AWS Provider
provider "aws" {
  region = "ap-northeast-2" # 원하는 리전으로 변경하세요
}

# VPC 모듈
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.9"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group_rule" "allow_management_ec2_to_eks" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = aws_security_group.management_ec2.id
  description              = "Allow management EC2 to communicate with EKS API Server"
}

# EKS 모듈
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "my-eks-cluster"
  cluster_version = "1.27"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t2.medium"]
    disk_size      = 20 # 스토리지 용량을 8GB로 설정

    attach_cluster_primary_security_group = true
  }

  eks_managed_node_groups = {
    default_node_group = {
      min_size     = 2
      max_size     = 10
      desired_size = 2

      instance_types = ["t2.medium"]
      capacity_type  = "ON_DEMAND"

      key_name = "eks-practice-key" # 여기에 키 이름을 지정합니다
    }
  }

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true  # 퍼블릭 액세스 허용

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# EC2 인스턴스를 위한 보안 그룹
resource "aws_security_group" "management_ec2" {
  name        = "management-ec2-sg"
  description = "Security group for management EC2 instance"
  vpc_id      = module.vpc.vpc_id

  # 기존의 SSH from anywhere 규칙을 제거하고, 
  # Bastion에서의 SSH 접근은 위에서 추가한 aws_security_group_rule로 처리됩니다.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTPS traffic to EKS API server"
  }

  tags = {
    Name = "management-ec2-sg"
  }
}

# EC2 인스턴스를 위한 IAM 역할
resource "aws_iam_role" "management_ec2_role" {
  name = "management-ec2-role"

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
}

resource "aws_iam_role_policy_attachment" "management_ec2_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  # 주의: 실제 환경에서는 더 제한적인 정책을 사용해야 합니다
  role       = aws_iam_role.management_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "management_ec2_eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.management_ec2_role.name
}

resource "aws_iam_instance_profile" "management_ec2_profile" {
  name = "management-ec2-profile"
  role = aws_iam_role.management_ec2_role.name
}

resource "aws_instance" "management_ec2" {
  ami           = "ami-056a29f2eddc40520"  # Ubuntu 22.04 LTS (ap-northeast-2 리전)
  instance_type = "t2.micro"
  subnet_id     = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.management_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.management_ec2_profile.name
  key_name               = "eks-practice-key"  # 여기에 실제 키 페어 이름을 입력하세요

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y git
              apt-get install -y git unzip
              snap install kubectl --classic
              snap install terraform --classic
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install
              echo "export EKS_CLUSTER_NAME=${module.eks.cluster_name}" >> /etc/environment
              EOF

  tags = {
    Name = "EKS-Management-EC2-Ubuntu"
  }
}

resource "aws_security_group" "bastion" {
  name        = "bastion-sg"
  description = "Security group for Bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 실제 운영 환경에서는 이를 제한해야 합니다
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# Bastion 호스트
resource "aws_instance" "bastion" {
  ami           = "ami-056a29f2eddc40520"  # Ubuntu 22.04 LTS (ap-northeast-2 리전)
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]  # 퍼블릭 서브넷에 배치
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = "eks-practice-key"
  associate_public_ip_address = true

  tags = {
    Name = "EKS-Bastion"
  }
}

# 기존 관리용 EC2 인스턴스의 보안 그룹에 규칙 추가
resource "aws_security_group_rule" "allow_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.management_ec2.id
}

# Bastion 호스트 public IP 출력
output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "The public IP address of the Bastion host"
}

# 출력
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "ssh_command_bastion" {
  value = "ssh -i ${aws_instance.bastion.key_name}.pem ubuntu@${aws_instance.bastion.public_ip}"
}

output "ssh_command_management_ec2" {
  value = "ssh -i ${aws_instance.management_ec2.key_name}.pem ubuntu@${aws_instance.management_ec2.private_ip}"
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}