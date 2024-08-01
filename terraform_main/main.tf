terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }
}

provider "aws" {
  alias  = "seoul"
  region = "ap-northeast-2"
}

data "aws_region" "seoul" {
  provider = aws.seoul
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# 랜덤 문자열 생성 (역할 이름 중복 방지용)
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.streaming_cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.streaming_cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.streaming_cluster.name]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.streaming_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.streaming_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.streaming_cluster.name]
    command     = "aws"
  }
}

# VPC 생성 (한국)
resource "aws_vpc" "vpc_seoul" {
  provider             = aws.seoul
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-seoul"
  }
}

# 서브넷 생성 (한국)
resource "aws_subnet" "subnet_seoul" {
  count                   = 2
  provider                = aws.seoul
  vpc_id                  = aws_vpc.vpc_seoul.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = count.index == 0 ? "ap-northeast-2a" : "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-seoul-${count.index + 1}"
  }
}

# VPC에 인터넷 게이트웨이 추가
resource "aws_internet_gateway" "igw" {
  provider = aws.seoul
  vpc_id   = aws_vpc.vpc_seoul.id

  tags = {
    Name = "main-igw"
  }
}

# 라우팅 테이블 생성 및 연결
resource "aws_route_table" "main" {
  provider = aws.seoul
  vpc_id   = aws_vpc.vpc_seoul.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "main-route-table"
  }
}

resource "aws_route_table_association" "subnet_seoul" {
  count          = 2
  provider       = aws.seoul
  subnet_id      = aws_subnet.subnet_seoul[count.index].id
  route_table_id = aws_route_table.main.id
}

# 새로운 SSH 키 생성
resource "tls_private_key" "eks_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS 키 페어 생성
resource "aws_key_pair" "eks_key_pair" {
  provider   = aws.seoul
  key_name   = "eks-practice-key-${random_string.suffix.result}"
  public_key = tls_private_key.eks_ssh_key.public_key_openssh
}

# 프라이빗 키를 로컬 파일로 저장
resource "local_file" "eks_private_key" {
  content         = tls_private_key.eks_ssh_key.private_key_pem
  filename        = "eks-practice-key-${random_string.suffix.result}.pem"
  file_permission = "0400"
}

# EKS 클러스터 역할 생성 (중복 방지)
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-${random_string.suffix.result}"

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
  provider   = aws.seoul
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS 클러스터 생성 (한국)
resource "aws_eks_cluster" "streaming_cluster" {
  provider = aws.seoul
  name     = "streaming-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.subnet_seoul[*].id
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # OIDC 프로바이더 활성화를 위한 설정
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_kms_key.eks_secrets
  ]
}

# EKS 클러스터가 완전히 생성될 때까지 기다림
#resource "null_resource" "wait_for_nodes" {
#  depends_on = [aws_eks_node_group.streaming_node_group]
#
#  provisioner "local-exec" {
#    interpreter = ["/bin/bash", "-c"]
#    command = <<-EOF
#      #!/bin/bash
#      set -e
#
#      CLUSTER_NAME="${aws_eks_cluster.streaming_cluster.name}"
#      REGION="${data.aws_region.current.name}"
#
#      echo "Updating kubeconfig for EKS cluster: $CLUSTER_NAME in region: $REGION"
#      aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME"
#
#      echo "Getting correct context"
#      CONTEXT=$(kubectl config get-contexts -o name | grep "$CLUSTER_NAME")
#
#      echo "Using context: $CONTEXT"
#      kubectl config use-context "$CONTEXT"
#
#      echo "Waiting for at least one node to be ready"
#      while ! kubectl --context "$CONTEXT" get nodes --no-headers 2>/dev/null | grep -q " Ready"; do
#        echo "Waiting for EKS nodes to be ready..."
#        sleep 10
#      done
#
#      DESIRED_COUNT=${aws_eks_node_group.streaming_node_group.scaling_config[0].desired_size}
#      echo "Waiting for all $DESIRED_COUNT nodes to be ready"
#      while true; do
#        READY_COUNT=$(kubectl --context "$CONTEXT" get nodes --no-headers 2>/dev/null | grep " Ready" | wc -l)
#        if [ "$READY_COUNT" -eq "$DESIRED_COUNT" ]; then
#          echo "All $DESIRED_COUNT nodes are ready"
#          break
#        fi
#        echo "Waiting for all nodes to be ready. Ready: $READY_COUNT, Desired: $DESIRED_COUNT"
#        sleep 10
#      done
#    EOF
#  }
#}

# KMS 키 생성 (OIDC 프로바이더 활성화를 위해 필요)
resource "aws_kms_key" "eks_secrets" {
  provider            = aws.seoul
  description         = "KMS key for EKS cluster secrets encryption"
  enable_key_rotation = true
}

# OIDC 프로바이더 생성
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.streaming_cluster.identity[0].oidc[0].issuer
}

#resource "aws_eks_addon" "coredns" {
#  cluster_name = aws_eks_cluster.streaming_cluster.name
#  addon_name   = "coredns"
#  depends_on   = [null_resource.wait_for_nodes]
#}
#
#resource "aws_eks_addon" "kube_proxy" {
#  cluster_name = aws_eks_cluster.streaming_cluster.name
#  addon_name   = "kube-proxy"
#  depends_on   = [null_resource.wait_for_nodes]
#}
#
#resource "aws_eks_addon" "vpc_cni" {
#  cluster_name = aws_eks_cluster.streaming_cluster.name
#  addon_name   = "vpc-cni"
#  depends_on   = [null_resource.wait_for_nodes]
#}

# 노드 그룹 역할 생성
resource "aws_iam_role" "eks_node_group_role" {
  name = "eks-node-group-role-${random_string.suffix.result}"

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
  provider   = aws.seoul
  policy_arn = each.value
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_efs_policy" {
  provider   = aws.seoul
  policy_arn = aws_iam_policy.efs_access_policy.arn
  role       = aws_iam_role.eks_node_group_role.name
}

# 노드 그룹 생성 (한국)
resource "aws_eks_node_group" "streaming_node_group" {
  provider         = aws.seoul
  cluster_name     = aws_eks_cluster.streaming_cluster.name
  node_group_name  = "seoul-nodegroup"
  node_role_arn    = aws_iam_role.eks_node_group_role.arn
  subnet_ids       = aws_subnet.subnet_seoul[*].id

  remote_access {
    ec2_ssh_key               = aws_key_pair.eks_key_pair.key_name
    source_security_group_ids = [aws_security_group.eks_sg.id]
  }

  scaling_config {
    desired_size = 2
    max_size     = 10
    min_size     = 2
  }

  instance_types = ["t3.xlarge"]

  labels = {
    "region" = "seoul"
  }

  tags = {
    "Name" = "seoul-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_policies,
    aws_eks_cluster.streaming_cluster
  ]
}

# 보안 그룹 생성 (한국)
resource "aws_security_group" "eks_sg" {
  provider    = aws.seoul
  name        = "eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.vpc_seoul.id

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

resource "aws_security_group_rule" "allow_efs_outbound" {
  provider                 = aws.seoul
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.efs_sg.id
  security_group_id        = aws_security_group.eks_sg.id
}

# eks 접근용 ec2 생성



resource "aws_security_group" "ec2_sg" {
  provider    = aws.seoul
  name        = "ec2-sg"
  description = "Security group for EC2 instance"
  vpc_id      = aws_vpc.vpc_seoul.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg"
  }
}

# EC2 인스턴스 생성
resource "aws_instance" "eks_access" {
  provider               = aws.seoul
  ami                    = "ami-056a29f2eddc40520"  # Ubuntu 22.04 LTS (ap-northeast-2)
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.eks_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.subnet_seoul[0].id
  iam_instance_profile   = aws_iam_instance_profile.eks_access_profile.name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y git unzip jq

              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x kubectl
              mv kubectl /usr/local/bin/

              # Install AWS CLI v2
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install

              # Install eksctl
              curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
              mv /tmp/eksctl /usr/local/bin

              # Install Helm
              curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
              EOF

  tags = {
    Name = "EKS Access Instance"
  }
}

# EC2 인스턴스에 EIP 연결
#resource "aws_eip" "eks_access" {
#  provider = aws.seoul
#  instance = aws_instance.eks_access.id
#  domain   = "vpc"
#
#  tags = {
#    Name = "EKS Access EIP"
#  }
#}

# EKS 클러스터 접근을 위한 IAM 역할
resource "aws_iam_role" "eks_access_role" {
  provider = aws.seoul
  name     = "eks-access-role-${random_string.suffix.result}"

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

# EKS 접근을 위한 IAM 정책
resource "aws_iam_role_policy_attachment" "eks_access_policy" {
  provider   = aws.seoul
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_access_role.name

  depends_on = [aws_iam_role.eks_access_role]
}

# EC2 인스턴스 프로파일
resource "aws_iam_instance_profile" "eks_access_profile" {
  provider = aws.seoul
  name     = "eks-access-profile"
  role     = aws_iam_role.eks_access_role.name

  depends_on = [aws_iam_role.eks_access_role]
}

# EFS CSI 드라이버 설치를 위한 Helm 차트
resource "helm_release" "aws_efs_csi_driver" {
  depends_on = [aws_eks_node_group.streaming_node_group]
  name       = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  namespace  = "kube-system"

  create_namespace = true

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/eks/aws-efs-csi-driver"
  }

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.efs_csi_role.arn
  }  

  set {
    name  = "storageClasses[0].parameters.fileSystemId"
    value = aws_efs_file_system.eks_efs.id
  }

  set {
    name  = "storageClasses[0].name"
    value = "efs-sc"
  }
}

# IRSA (IAM Roles for Service Accounts) 설정
data "aws_iam_policy_document" "efs_csi_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "efs_csi_role" {
  name = "eks-efs-csi-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub": "system:serviceaccount:kube-system:efs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_policy" {
  policy_arn = aws_iam_policy.efs_access_policy.arn
  role       = aws_iam_role.efs_csi_role.name
}

# EKS OIDC 프로바이더 생성
data "tls_certificate" "eks" {
  url = aws_eks_cluster.streaming_cluster.identity[0].oidc[0].issuer
}

# 1. EFS 파일 시스템 생성
resource "aws_efs_file_system" "eks_efs" {
  provider = aws.seoul
  creation_token = "eks-efs-${random_string.suffix.result}"

  tags = {
    Name = "EKS-EFS"
  }
}

# 2. EFS 마운트 타겟 생성
resource "aws_efs_mount_target" "eks_efs_mount" {
  count           = 2
  provider        = aws.seoul
  file_system_id  = aws_efs_file_system.eks_efs.id
  subnet_id       = aws_subnet.subnet_seoul[count.index].id
  security_groups = [aws_security_group.efs_sg.id]
}

# 3. EFS용 보안 그룹 생성
resource "aws_security_group" "efs_sg" {
  provider    = aws.seoul
  name        = "efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.vpc_seoul.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_sg.id, aws_eks_node_group.streaming_node_group.resources[0].remote_access_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "efs-sg"
  }
}

resource "aws_security_group_rule" "allow_nfs_from_efs" {
  provider                 = aws.seoul
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.efs_sg.id
  security_group_id        = aws_security_group.eks_sg.id

  depends_on = [aws_security_group.eks_sg, aws_security_group.efs_sg]
}

# 4. IAM 정책 생성 및 역할에 연결
resource "aws_iam_policy" "efs_access_policy" {
  provider    = aws.seoul
  name        = "EFSAccessPolicy-${random_string.suffix.result}"
  path        = "/"
  description = "IAM policy for EFS access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:TagResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = "arn:aws:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:file-system/${aws_efs_file_system.eks_efs.id}"
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" : "arn:aws:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:access-point/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "efs_csi_driver_policy" {
  provider    = aws.seoul
  name        = "AmazonEKS_EFS_CSI_Driver_Policy-${random_string.suffix.result}"
  description = "IAM policy for EFS CSI Driver"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/efs.csi.aws.com/cluster": "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = "elasticfilesystem:DeleteAccessPoint"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_driver_policy_attachment" {
  provider   = aws.seoul
  policy_arn = aws_iam_policy.efs_csi_driver_policy.arn
  role       = aws_iam_role.efs_csi_role.name
}

resource "aws_iam_role_policy_attachment" "efs_policy_attachment" {
  provider   = aws.seoul
  policy_arn = aws_iam_policy.efs_access_policy.arn
  role       = aws_iam_role.eks_node_group_role.name
}

# SSH 명령어 출력 (키 파일 경로 업데이트)
output "ssh_command" {
  value       = "ssh -i ${local_file.eks_private_key.filename} ubuntu@${aws_instance.eks_access.public_ip}"
  description = "SSH command to connect to the EC2 instance"
}
