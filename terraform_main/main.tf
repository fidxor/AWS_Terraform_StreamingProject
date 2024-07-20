provider "aws" {
  region = "ap-northeast-2"
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
resource "aws_subnet" "k8s_subnet_az1" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet-az1"
  }
}

resource "aws_subnet" "k8s_subnet_az2" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-subnet-az2"
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
resource "aws_route_table_association" "k8s_rta_az1" {
  subnet_id      = aws_subnet.k8s_subnet_az1.id
  route_table_id = aws_route_table.k8s_rt.id
}

resource "aws_route_table_association" "k8s_rta_az2" {
  subnet_id      = aws_subnet.k8s_subnet_az2.id
  route_table_id = aws_route_table.k8s_rt.id
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

  provisioner "local-exec" {
    command = "chmod 400 ${path.module}/kubespray-key.pem"
  }
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
    from_port   = 30000
    to_port     = 32767
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
    from_port   = 30000
    to_port     = 32767
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
}

# 마스터 노드 생성
resource "aws_instance" "master" {
  ami                    = "ami-056a29f2eddc40520"  # Ubuntu 20.04 LTS
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.kubespray_key.key_name
  vpc_security_group_ids = [aws_security_group.master_sg.id]
  subnet_id              = aws_subnet.k8s_subnet_az1.id

  tags = {
    Name = "k8s-master"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3 python3-pip
              echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/ubuntu
              sed -i 's/^Defaults.*requiretty/#Defaults requiretty/' /etc/sudoers
              EOF
}

# 워커 노드 생성
resource "aws_instance" "worker" {
  count                  = 2
  ami                    = "ami-056a29f2eddc40520"  # Ubuntu 20.04 LTS
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.kubespray_key.key_name
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  subnet_id              = count.index == 0 ? aws_subnet.k8s_subnet_az1.id : aws_subnet.k8s_subnet_az2.id

  tags = {
    Name = "k8s-worker-${count.index + 1}"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3 python3-pip
              echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/ubuntu
              sed -i 's/^Defaults.*requiretty/#Defaults requiretty/' /etc/sudoers
              EOF
}

# Kubespray 인스턴스 생성
resource "aws_instance" "kubespray" {
  ami                    = "ami-056a29f2eddc40520"  # Ubuntu 20.04 LTS
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.kubespray_key.key_name
  vpc_security_group_ids = [aws_security_group.kubespray_sg.id]
  subnet_id              = aws_subnet.k8s_subnet_az1.id

  tags = {
    Name = "kubespray-instance"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3-pip awscli
              pip3 install ansible

              # 새로운 SSH 키 생성
              ssh-keygen -t rsa -b 4096 -f /home/ubuntu/.ssh/kubespray_key -N ""
              chown ubuntu:ubuntu /home/ubuntu/.ssh/kubespray_key*

              # 공개 키 내용을 변수에 저장
              PUBKEY=$(cat /home/ubuntu/.ssh/kubespray_key.pub)

              # 마스터 노드에 공개 키 추가
              ssh -i /home/ubuntu/.ssh/kubespray_key -o StrictHostKeyChecking=no ubuntu@${aws_instance.master.private_ip} "echo $PUBKEY >> ~/.ssh/authorized_keys"

              # 워커 노드에 공개 키 추가
              for IP in ${join(" ", aws_instance.worker[*].private_ip)}; do
                ssh -i /home/ubuntu/.ssh/kubespray_key -o StrictHostKeyChecking=no ubuntu@$IP "echo $PUBKEY >> ~/.ssh/authorized_keys"
              done

              git clone https://github.com/kubernetes-sigs/kubespray.git
              cd kubespray
              pip3 install -r requirements.txt

              # known_hosts 파일 생성
              ssh-keyscan -H ${aws_instance.master.private_ip} >> /home/ubuntu/.ssh/known_hosts
              for IP in ${join(" ", aws_instance.worker[*].private_ip)}; do
                ssh-keyscan -H $IP >> /home/ubuntu/.ssh/known_hosts
              done

              chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts
              EOF
}

# ArgoCD 로드 밸런서 생성
resource "aws_lb" "argocd_lb" {
  name               = "argocd-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.master_sg.id]
  subnets            = [aws_subnet.k8s_subnet_az1.id, aws_subnet.k8s_subnet_az2.id]

  enable_deletion_protection = false

  tags = {
    Name = "argocd-lb"
  }
}

resource "aws_lb_target_group" "argocd_tg" {
  name     = "argocd-tg"
  port     = 30080  # ArgoCD NodePort 번호
  protocol = "HTTP"
  vpc_id   = aws_vpc.k8s_vpc.id

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
  }
}

resource "aws_lb_target_group_attachment" "argocd_tg_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.argocd_tg.arn
  target_id        = aws_instance.worker[count.index].id
  port             = 30080  # ArgoCD NodePort 번호
}

resource "aws_lb_listener" "argocd_listener" {
  load_balancer_arn = aws_lb.argocd_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.argocd_tg.arn
  }
}

# 출력

output "argocd_lb_dns_name" {
  value = aws_lb.argocd_lb.dns_name
}

output "kubespray_public_ip" {
  value = aws_instance.kubespray.public_ip
}

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "master_private_ip" {
  value = aws_instance.master.private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}