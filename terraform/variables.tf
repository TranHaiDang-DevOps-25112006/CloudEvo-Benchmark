variable "aws_region" {
  description = "AWS Region triển khai hạ tầng CloudEvo"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên định danh dự án"
  type        = string
  default     = "cloudevo"
}

variable "scenario_case" {
  description = "Chọn kịch bản triển khai (1: Single EC2 Stateless, 2: Single EC2 Monolith, 3: Decoupled 2 EC2, 4: EC2 Web + Managed RDS)"
  type        = number
  default     = 4

  validation {
    condition     = contains([1, 2, 3, 4], var.scenario_case)
    error_message = "Giá trị scenario_case phải là 1, 2, 3 hoặc 4."
  }
}

variable "vpc_cidr" {
  description = "Dải mạng CIDR cho cloudevo-vpc"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "Loại máy chủ EC2 cho tầng Web và DB tự quản"
  type        = string
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "Loại máy chủ Amazon RDS PostgreSQL (Trường hợp 4)"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_multi_az" {
  description = "Bật/tắt chế độ Multi-AZ cho RDS (false cho Dev/Benchmark tiết kiệm chi phí, true cho Production)"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Tên cơ sở dữ liệu PostgreSQL"
  type        = string
  default     = "cloudevo_db"
}

variable "db_username" {
  description = "Tài khoản quản trị Database"
  type        = string
  default     = "cloudevo"
}

variable "db_password" {
  description = "Mật khẩu Database (Truyền qua biến môi trường hoặc tfvars)"
  type        = string
  default     = "CloudEvo2026StrongPass!"
  sensitive   = true
}

variable "s3_backup_bucket_name" {
  description = "Tên S3 Bucket lưu trữ bản sao lưu pg_dump"
  type        = string
  default     = "cloudevo-backup-dangth-iac"
}

variable "create_s3_bucket" {
  description = "Tự động tạo S3 Bucket mới cho môi trường IaC"
  type        = bool
  default     = true
}
