provider "aws" {
  alias  = "korea"
  region = "ap-northeast-2"
}

provider "aws" {
  alias  = "us"
  region = "us-west-2"
}

# VPC 생성 (한국)
resource "aws_vpc" "vpc_korea" {
  provider             = aws.korea
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-korea"
  }
}

# 서브넷 생성 (한국)
resource "aws_subnet" "subnet_korea" {
  count                   = 2
  provider                = aws.korea
  vpc_id                  = aws_vpc.vpc_korea.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = count.index == 0 ? "ap-northeast-2a" : "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-korea-${count.index + 1}"
  }
}

# VPC에 인터넷 게이트웨이 추가
resource "aws_internet_gateway" "igw" {
  provider = aws.korea
  vpc_id   = aws_vpc.vpc_korea.id

  tags = {
    Name = "main-igw"
  }
}

# 라우팅 테이블 생성 및 연결
resource "aws_route_table" "main" {
  provider = aws.korea
  vpc_id   = aws_vpc.vpc_korea.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "main-route-table"
  }
}

resource "aws_route_table_association" "subnet_korea" {
  count          = 2
  provider       = aws.korea
  subnet_id      = aws_subnet.subnet_korea[count.index].id
  route_table_id = aws_route_table.main.id
}

# EKS 클러스터 역할 생성
resource "aws_iam_role" "eks_cluster_role" {
  provider = aws.korea
  name     = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# EKS 클러스터 정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  provider   = aws.korea
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS 클러스터 생성 (한국)
resource "aws_eks_cluster" "streaming_cluster" {
  provider = aws.korea
  name     = "streaming-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.subnet_korea[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# 노드 그룹 역할 생성
resource "aws_iam_role" "eks_node_group_role" {
  provider = aws.korea
  name     = "eks-node-group-role"

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

# 노드 그룹 정책 연결
resource "aws_iam_role_policy_attachment" "eks_node_group_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])
  provider   = aws.korea
  policy_arn = each.value
  role       = aws_iam_role.eks_node_group_role.name
}

# 노드 그룹 생성 (한국)
resource "aws_eks_node_group" "streaming_node_group" {
  provider         = aws.korea
  cluster_name     = aws_eks_cluster.streaming_cluster.name
  node_group_name  = "korea-nodegroup"
  node_role_arn    = aws_iam_role.eks_node_group_role.arn
  subnet_ids       = aws_subnet.subnet_korea[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  labels = {
    "region" = "korea"
  }

  tags = {
    "Name" = "korea-node"
  }

  remote_access {
    ec2_ssh_key               = "monitoring"  # AWS에서 생성한 키 페어 이름으로 변경
    source_security_group_ids = [aws_security_group.eks_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_node_group_policies]
}

# 보안 그룹 생성 (한국)
resource "aws_security_group" "eks_sg" {
  provider    = aws.korea
  name        = "eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.vpc_korea.id

  dynamic "ingress" {
    for_each = [22, 80, 3000, 3100, 9090]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}