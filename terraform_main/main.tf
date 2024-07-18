provider "aws" {
  region = "ap-northeast-2"
}

# 원본 영상을 저장할 S3 버킷 생성
resource "aws_s3_bucket" "source_bucket" {
  bucket = "24kng-source-video-bucket" # 버킷 이름 설정
}

# 트랜스코딩된 영상을 저장할 S3 버킷 생성
resource "aws_s3_bucket" "destination_bucket" {
  bucket = "24kng-transcoded-video-bucket" #버킷 이름 설정
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_subnet" "k8s_subnet" {
  count                   = 3
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

resource "aws_route_table" "k8s_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s-rt"
  }
}

resource "aws_route_table_association" "k8s_rta" {
  count          = 3
  subnet_id      = aws_subnet.k8s_subnet[count.index].id
  route_table_id = aws_route_table.k8s_rt.id
}

resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg"
  description = "Security group for Kubernetes cluster"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-sg"
  }
}

resource "aws_launch_template" "k8s_node" {
  name_prefix   = "k8s-node-"
  image_id      = "ami-056a29f2eddc40520" # Ubuntu 20.04 LTS
  instance_type = "t3.medium"

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "k8s-node"
    }
  }
}

resource "aws_autoscaling_group" "k8s_asg" {
  name                = "k8s-asg"
  vpc_zone_identifier = aws_subnet.k8s_subnet[*].id
  desired_capacity    = 3
  max_size            = 5
  min_size            = 1

  launch_template {
    id      = aws_launch_template.k8s_node.id
    version = "$Latest"
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/k8s-cluster"
    value               = "owned"
    propagate_at_launch = true
  }
}

output "asg_name" {
  value = aws_autoscaling_group.k8s_asg.name
}