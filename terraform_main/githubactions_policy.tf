#data "aws_iam_openid_connect_provider" "github_actions" {
#  url = "https://token.actions.githubusercontent.com"
#}

# OIDC 프로바이더 설정
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# GitHub Actions를 위한 IAM 역할
# GitHub Actions를 위한 IAM 역할
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {        
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub": "repo:kkkikki/24KNG_web:*"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/gjkim"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# GitHub Actions 역할을 위한 정책
resource "aws_iam_policy" "github_actions_policy" {
  name        = "github-actions-eks-policy"
  description = "Policy for GitHub Actions EKS role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "eks:*",
          "ec2:*",
          "elasticfilesystem:*",
          "iam:*",
          "kms:*",
          "s3:*",
          "autoscaling:*",
          "elasticloadbalancing:*",
          "cloudwatch:*",
          "logs:*",
          "cloudformation:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# GitHub Actions 역할에 정책 연결
resource "aws_iam_role_policy_attachment" "github_actions_policy_attachment" {
  policy_arn = aws_iam_policy.github_actions_policy.arn
  role       = aws_iam_role.github_actions_role.name
}

# GitHub Actions 역할에 EKS 권한 부여
# GitHub Actions 역할에 EKS 클러스터 정책 연결
resource "aws_iam_role_policy_attachment" "github_actions_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.github_actions_role.name
}

# GitHub Actions 역할에 커스텀 정책 연결
resource "aws_iam_role_policy_attachment" "github_actions_custom_policy" {
  policy_arn = aws_iam_policy.github_actions_policy.arn
  role       = aws_iam_role.github_actions_role.name
}

# IAM 사용자를 위한 TagSession 정책
resource "aws_iam_policy" "user_tag_session_policy" {
  name        = "UserTagSessionPolicy"
  path        = "/"
  description = "Allow sts:TagSession"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:TagSession"
        Resource = "*"
      },
    ]
  })
}

# IAM 사용자에게 TagSession 정책 연결
resource "aws_iam_user_policy_attachment" "user_tag_session_attach" {
  user       = "gjkim"
  policy_arn = aws_iam_policy.user_tag_session_policy.arn
}

# 출력 설정
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "ARN of the IAM role for GitHub Actions"
}