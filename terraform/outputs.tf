output "active_scenario_case" {
  description = "Kịch bản kiến trúc đang được kích hoạt qua Terraform"
  value       = "Scenario Case ${var.scenario_case}"
}

output "vpc_id" {
  description = "ID của VPC được khởi tạo tự động"
  value       = aws_vpc.main.id
}

output "web_ec2_public_ip" {
  description = "Địa chỉ Public IPv4 của máy chủ Web EC2"
  value       = aws_instance.web_ec2.public_ip
}

output "health_check_url" {
  description = "Đường dẫn kiểm tra trực tiếp trạng thái /health"
  value       = "http://${aws_instance.web_ec2.public_ip}/health"
}

output "db_connection_target" {
  description = "Địa chỉ kết nối tầng Database (Private IP hoặc RDS Endpoint)"
  value       = local.db_host
}

output "rds_endpoint" {
  description = "RDS PostgreSQL DNS Endpoint (Chỉ hiển thị ở Trường hợp 4)"
  value       = var.scenario_case == 4 ? aws_db_instance.rds_postgres[0].endpoint : "N/A (Not Case 4)"
}
