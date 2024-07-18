provider "aws" {
  region = "ap-northeast-2" # 원하는 리전으로 변경 가능
}

# VPC 생성
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "k8s-vpc"
  }
}

# 서브넷 생성
resource "aws_subnet" "k8s_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a" # 가용 영역 설정
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet"
  }
}

# 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

# 라우트 테이블 생성
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

# 서브넷과 라우트 테이블 연결
resource "aws_route_table_association" "k8s_rta" {
  subnet_id      = aws_subnet.k8s_subnet.id
  route_table_id = aws_route_table.k8s_rt.id
}

# 마스터 노드용 키 페어 생성
resource "tls_private_key" "master_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "master_key" {
  key_name   = "k8s-master-key"
  public_key = tls_private_key.master_key.public_key_openssh
}

# 키 페어 파일로 저장
resource "local_file" "master_key_file" {
  content  = tls_private_key.master_key.private_key_pem
  filename = "${path.module}/k8s-master-key.pem"
}

# 마스터 노드 보안 그룹
resource "aws_security_group" "master_sg" {
  name        = "k8s-master-sg"
  description = "Security group for Kubernetes master node"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.kubespray_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 워커 노드 보안 그룹
resource "aws_security_group" "worker_sg" {
  name        = "k8s-worker-sg"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.master_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.kubespray_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 마스터 노드 생성
resource "aws_instance" "master" {
  ami                    = "ami-056a29f2eddc40520" # Ubuntu 20.04 LTS
  instance_type          = "t2.medium"
  key_name               = aws_key_pair.master_key.key_name
  vpc_security_group_ids = [aws_security_group.master_sg.id]
  subnet_id              = aws_subnet.k8s_subnet.id

  tags = {
    Name = "k8s-master"
  }

  user_data = <<-EOF
              #!/bin/bash
              echo '${tls_private_key.kubespray_key.public_key_openssh}' >> /home/ubuntu/.ssh/authorized_keys
              EOF
}

# Auto Scaling 그룹 설정
resource "aws_launch_configuration" "worker_config" {
  name_prefix     = "k8s-worker-"
  image_id        = "ami-056a29f2eddc40520" # Ubuntu 20.04 LTS
  instance_type   = "t2.medium"
  security_groups = [aws_security_group.worker_sg.id]
  key_name        = aws_key_pair.master_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              echo '${tls_private_key.kubespray_key.public_key_openssh}' >> /home/ubuntu/.ssh/authorized_keys
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker_asg" {
  name                = "k8s-worker-asg"
  vpc_zone_identifier = [aws_subnet.k8s_subnet.id]
  desired_capacity    = 2
  max_size            = 5
  min_size            = 1

  launch_configuration = aws_launch_configuration.worker_config.name

  tag {
    key                 = "Name"
    value               = "k8s-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/24kng_cluster"
    value               = "owned"
    propagate_at_launch = true
  }
}

# Kubespray용 키 페어 생성
resource "tls_private_key" "kubespray_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "kubespray_key" {
  key_name   = "kubespray-key"
  public_key = tls_private_key.kubespray_key.public_key_openssh
}

# Kubespray 키 페어 파일로 저장
resource "local_file" "kubespray_key_file" {
  content  = tls_private_key.kubespray_key.private_key_pem
  filename = "${path.module}/kubespray-key.pem"
}

# Kubespray 인스턴스용 보안 그룹
resource "aws_security_group" "kubespray_sg" {
  name        = "kubespray-sg"
  description = "Security group for Kubespray instance"
  vpc_id      = aws_vpc.k8s_vpc.id

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

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.k8s_vpc.cidr_block]
  }
}

# Kubespray 인스턴스 생성
resource "aws_instance" "kubespray" {
  ami                    = "ami-056a29f2eddc40520" # Ubuntu 20.04 LTS
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.kubespray_key.key_name
  vpc_security_group_ids = [aws_security_group.kubespray_sg.id]
  subnet_id              = aws_subnet.k8s_subnet.id

  tags = {
    Name = "kubespray-instance"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3-pip awscli
              pip3 install ansible
              git clone https://github.com/kubernetes-sigs/kubespray.git
              cd kubespray
              pip3 install -r requirements.txt

              echo '${tls_private_key.master_key.private_key_pem}' > /home/ubuntu/.ssh/id_rsa
              chmod 600 /home/ubuntu/.ssh/id_rsa
              chown ubuntu:ubuntu /home/ubuntu/.ssh/id_rsa

              ssh-keyscan -H ${aws_instance.master.private_ip} >> /home/ubuntu/.ssh/known_hosts

              WORKER_IPS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=k8s-worker" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)

              for IP in $WORKER_IPS; do
                ssh-keyscan -H $IP >> /home/ubuntu/.ssh/known_hosts
              done
              EOF
}

# 출력
output "kubespray_public_ip" {
  value = aws_instance.kubespray.public_ip
}

output "kubespray_private_key" {
  value     = tls_private_key.kubespray_key.private_key_pem
  sensitive = true
}

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "master_private_key" {
  value     = tls_private_key.master_key.private_key_pem
  sensitive = true
}