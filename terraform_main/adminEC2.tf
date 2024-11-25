# Create a new security group
resource "aws_security_group" "admin_server_sg" {
  provider    = aws.seoul
  name        = "admin-server-sg"
  description = "Security group for Admin server"
  vpc_id      = aws_vpc.vpc_seoul.id

  # Inbound rules
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8888
    to_port     = 8888
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
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rule (allow all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance
resource "aws_instance" "admin_server" {
  provider      = aws.seoul
  ami           = "ami-056a29f2eddc40520"  # This AMI is for ap-northeast-2 (Seoul)
  instance_type = "t2.micro"
  key_name      = aws_key_pair.eks_key_pair.key_name
  subnet_id     = aws_subnet.subnet_seoul[0].id

  iam_instance_profile = aws_iam_instance_profile.admin_ec2_profile.name

  tags = {
    Name = "Admin-server"
  }

  # Use the newly created security group
  vpc_security_group_ids = [aws_security_group.admin_server_sg.id]
}

resource "aws_iam_role" "admin_ec2_role" {
  name = "admin-ec2-role"
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

resource "aws_iam_role_policy_attachment" "admin_ec2_rds_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
  role       = aws_iam_role.admin_ec2_role.name
}

resource "aws_iam_instance_profile" "admin_ec2_profile" {
  name = "admin-ec2-profile"
  role = aws_iam_role.admin_ec2_role.name
}