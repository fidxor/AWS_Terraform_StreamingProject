# RDS용 보안 그룹 생성
resource "aws_security_group" "rds_sg" {
  provider    = aws.seoul
  name        = "rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.vpc_seoul.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_sg.id, aws_security_group.admin_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# 새로운 파라미터 그룹 생성
resource "aws_db_parameter_group" "mariadb_utf8mb4" {
  family = "mariadb10.11"
  name   = "mariadb-utf8mb4"

  parameter {
    name  = "character_set_client"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_connection"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_database"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_filesystem"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_results"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_connection"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "MariaDB UTF8MB4 Parameter Group"
  }
}

resource "aws_db_instance" "mariadb_instance" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mariadb"
  engine_version       = "10.11.8"
  instance_class       = "db.t3.medium"
  identifier           = "database-24kng"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name   = aws_db_parameter_group.mariadb_utf8mb4.name
  publicly_accessible  = false
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "24kng-Database"
    Environment = "Development"
  }
}

# RDS 서브넷 그룹 생성
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = aws_subnet.subnet_seoul[*].id

  tags = {
    Name = "RDS subnet group"
  }
}