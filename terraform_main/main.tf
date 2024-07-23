# Configure the AWS Provider
provider "aws" {
  region = "ap-northeast-2"  # 서울 리전
}

# 키 페어 생성
resource "tls_private_key" "k8s_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s_key_pair" {
  key_name   = "k8s-key-pair"
  public_key = tls_private_key.k8s_ssh_key.public_key_openssh
}

# 프라이빗 키를 로컬 파일로 저장
resource "local_file" "k8s_private_key" {
  content         = tls_private_key.k8s_ssh_key.private_key_pem
  filename        = "${path.module}/k8s_private_key.pem"
  file_permission = "0400"
}

# VPC 생성
resource "aws_vpc" "kubernetes_vpc" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "kubernetes-vpc"
    "kubernetes.io/cluster/kubernetes" = "owned"  # 이 줄 추가
  }
}

# 지원되는 가용 영역 명시적 지정
variable "availability_zones" {
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

# 서브넷 생성 (지정된 가용 영역)
resource "aws_subnet" "kubernetes_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.kubernetes_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "kubernetes-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/kubernetes" = "owned"  # 이 줄 추가
  }
}

# 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "kubernetes_igw" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  tags = {
    Name = "kubernetes-igw"
  }
}

# 라우트 테이블 생성
resource "aws_route_table" "kubernetes_route_table" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes_igw.id
  }

  tags = {
    Name = "kubernetes-route-table"
  }
}

# 서브넷을 라우트 테이블과 연결
resource "aws_route_table_association" "kubernetes_route_table_assoc" {
  count          = 2
  subnet_id      = aws_subnet.kubernetes_subnet[count.index].id
  route_table_id = aws_route_table.kubernetes_route_table.id
}

# 보안 그룹 생성
resource "aws_security_group" "kubernetes_sg" {
  name        = "kubernetes-sg"
  description = "Security group for Kubernetes cluster"
  vpc_id      = aws_vpc.kubernetes_vpc.id

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

resource "aws_security_group_rule" "allow_elb_health_check" {
  type        = "ingress"
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kubernetes_sg.id
}

# IAM 역할 생성
resource "aws_iam_role" "kubernetes_role" {
  name = "kubernetes-role"

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

# IAM 정책 생성 및 연결
resource "aws_iam_role_policy_attachment" "kubernetes_elb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = aws_iam_role.kubernetes_role.name
}

resource "aws_iam_role_policy_attachment" "kubernetes_ec2_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.kubernetes_role.name
}

# IAM 인스턴스 프로필 생성
resource "aws_iam_instance_profile" "kubernetes_profile" {
  name = "kubernetes-profile"
  role = aws_iam_role.kubernetes_role.name
}

# EC2 인스턴스 생성 (마스터 노드 1개, 워커 노드 2개)
resource "aws_instance" "kubernetes_nodes" {
  count                  = 3
  ami                    = "ami-056a29f2eddc40520"
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.kubernetes_subnet[count.index % 2].id
  vpc_security_group_ids = [aws_security_group.kubernetes_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.kubernetes_profile.name
  
  tags = {
    Name = count.index == 0 ? "kubernetes-master" : "kubernetes-worker-${count.index}"
  }

  key_name = aws_key_pair.k8s_key_pair.key_name

  root_block_device {
    volume_size = 20
  }

  user_data = templatefile("${path.module}/k8s_node_script.sh", {})
}

resource "aws_instance" "kubespray_instance" {
  ami                    = "ami-056a29f2eddc40520"
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.kubernetes_subnet[0].id
  vpc_security_group_ids = [aws_security_group.kubernetes_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.kubernetes_profile.name
  
  tags = {
    Name = "kubespray-instance"
  }

  key_name = aws_key_pair.k8s_key_pair.key_name

  root_block_device {
    volume_size = 20
  }

  user_data = templatefile("${path.module}/kubespray_script.sh", {
    tls_private_key = tls_private_key.k8s_ssh_key.private_key_pem
    master_ip       = aws_instance.kubernetes_nodes[0].private_ip
    worker1_ip      = aws_instance.kubernetes_nodes[1].private_ip
    worker2_ip      = aws_instance.kubernetes_nodes[2].private_ip
  })

  user_data_replace_on_change = true
}

# 탄력적 IP 할당 (마스터 노드용)
resource "aws_eip" "kubernetes_master_eip" {
  instance = aws_instance.kubernetes_nodes[0].id
  domain   = "vpc"
}

# 탄력적 IP 할당 (Kubespray 인스턴스용)
resource "aws_eip" "kubespray_eip" {
  instance = aws_instance.kubespray_instance.id
  domain   = "vpc"
}

output "master_public_ip" {
  value = aws_eip.kubernetes_master_eip.public_ip
}

output "worker_private_ips" {
  value = slice(aws_instance.kubernetes_nodes[*].private_ip, 1, 3)
}

output "kubespray_instance_public_ip" {
  value = aws_eip.kubespray_eip.public_ip
}

output "kubespray_instance_private_ip" {
  value = aws_instance.kubespray_instance.private_ip
}

output "ssh_private_key_path" {
  value = local_file.k8s_private_key.filename
}

output "ssh_command_kubespray" {
  value = "ssh -i ${local_file.k8s_private_key.filename} ubuntu@${aws_eip.kubespray_eip.public_ip}"
}

output "inventory_setup_command" {
  value = "On the Kubespray instance, run: python3 /home/ubuntu/kubespray/contrib/inventory_builder/inventory.py ${join(" ", aws_instance.kubernetes_nodes[*].private_ip)}"
}

output "hosts_yml_location" {
  value = "The hosts.yml file is located at: /home/ubuntu/kubespray/inventory/mycluster/hosts.yml on the Kubespray instance"
}