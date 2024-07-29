# Configure the AWS Provider
provider "aws" {
  region = "ap-northeast-2" # 서울 리전
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "ca-central-1"
  region = "ca-central-1"
}

# 키 페어 생성
resource "tls_private_key" "kops_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kops_key_pair" {
  key_name   = "k8s-key-pair"
  public_key = tls_private_key.kops_ssh_key.public_key_openssh
}

# 프라이빗 키를 로컬 파일로 저장
resource "local_file" "kops_private_key" {
  content         = tls_private_key.kops_ssh_key.private_key_pem
  filename        = "${path.module}/kops_private_key.pem"
  file_permission = "0400"
}

# 보안 그룹 생성
resource "aws_security_group" "kubernetes_sg" {
  name        = "kubernetes-sg"
  description = "Security group for Kubernetes cluster"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# kops용 S3 버킷 생성
resource "aws_s3_bucket" "my_bucket" {
  bucket        = "24kng-kops-bucket" # Replace with your desired bucket name
  force_destroy = true
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# kops 인스턴스에서 사용할 IAM Role 생성
resource "aws_iam_role" "kops_role" {
  name = "kops_role"

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

# kops에 필요한 추가 IAM 정책 생성
resource "aws_iam_policy" "kops_comprehensive_policy" {
  name        = "kops_comprehensive_policy"
  path        = "/"
  description = "Comprehensive IAM policy for kops"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "route53:*",
          "s3:*",
          "iam:*",
          "vpc:*",
          "autoscaling:*",
          "elasticloadbalancing:*",
          "cloudwatch:*",
          "events:*",
          "kms:*",
          "logs:*",
          "sns:*",
          "sqs:*",
          "ecr:*",
          "eks:*",
          "sts:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kops_comprehensive_policy_attachment" {
  policy_arn = aws_iam_policy.kops_comprehensive_policy.arn
  role       = aws_iam_role.kops_role.name
}

# IAM 인스턴스 프로파일 생성
resource "aws_iam_instance_profile" "kops_profile" {
  name = "kops_profile"
  role = aws_iam_role.kops_role.name
}

resource "aws_instance" "kops_instance" {
  ami                    = "ami-056a29f2eddc40520"
  instance_type          = "t2.medium"
  vpc_security_group_ids = [aws_security_group.kubernetes_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.kops_profile.name

  tags = {
    Name = "kops-instance"
  }

  key_name = aws_key_pair.kops_key_pair.key_name

  root_block_device {
    volume_size = 20
  }

  provisioner "file" {
    source      = "${path.module}/cluster-autoscaler.sh"
    destination = "/home/ubuntu/cluster-autoscaler.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.kops_ssh_key.private_key_pem
      host        = self.public_ip
    }
  }

  # user_data 크기 이슈로 압축
  user_data = base64gzip(
    templatefile("${path.module}/kops_script.sh", {
      s3bucketname      = aws_s3_bucket.my_bucket.bucket
      public_key        = tls_private_key.kops_ssh_key.public_key_openssh
      private_key       = tls_private_key.kops_ssh_key.private_key_pem
      slack_webhook_url = var.slack_webhook_url
    })
  )

  user_data_replace_on_change = true
}

output "kops_instance_public_ip" {
  value = aws_instance.kops_instance.public_ip
}

output "kops_instance_private_ip" {
  value = aws_instance.kops_instance.private_ip
}

output "ssh_private_key_path" {
  value = local_file.kops_private_key.filename
}

output "ssh_command_kops" {
  value = "ssh -i ${local_file.kops_private_key.filename} ubuntu@${aws_instance.kops_instance.public_ip}"
}