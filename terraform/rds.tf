# 1. Khởi tạo Private DB Subnet Group trải đều trên 2 AZ (ap-southeast-1a & 1b)
resource "aws_db_subnet_group" "rds_subnet_group" {
  count      = var.scenario_case == 4 ? 1 : 0
  name       = "${var.project_name}-db-subnet-group-iac"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group-iac"
  }
}

# 2. Khởi tạo Amazon RDS for PostgreSQL (Chỉ kích hoạt khi scenario_case == 4)
resource "aws_db_instance" "rds_postgres" {
  count             = var.scenario_case == 4 ? 1 : 0
  identifier        = "${var.project_name}-rds-postgres-iac"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.rds_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group[0].name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false
  multi_az               = var.rds_multi_az

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "${var.project_name}-rds-postgres-iac"
  }
}
