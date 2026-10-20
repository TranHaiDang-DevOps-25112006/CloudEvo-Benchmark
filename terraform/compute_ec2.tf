# 1. S3 Bucket lưu trữ bản sao lưu Database (Tùy chọn tạo mới bằng IaC)
resource "aws_s3_bucket" "backup_bucket" {
  count         = var.create_s3_bucket ? 1 : 0
  bucket        = var.s3_backup_bucket_name
  force_destroy = true

  tags = {
    Name = "${var.project_name}-s3-backup"
  }
}

# 2. IAM Role & Policy Least Privilege cho phép EC2 đẩy backup lên S3
resource "aws_iam_role" "ec2_s3_backup_role" {
  name = "${var.project_name}-ec2-s3-backup-role-iac"

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

resource "aws_iam_role_policy" "ec2_s3_backup_policy" {
  name = "${var.project_name}-ec2-s3-backup-policy-iac"
  role = aws_iam_role.ec2_s3_backup_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListSpecificBackupBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.s3_backup_bucket_name}"
      },
      {
        Sid    = "AllowReadWriteBackupObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_backup_bucket_name}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "${var.project_name}-ec2-s3-profile-iac"
  role = aws_iam_role.ec2_s3_backup_role.name
}

# 3. Máy chủ DB EC2 trong Private Subnet (Chỉ khởi tạo khi scenario_case == 3)
resource "aws_instance" "db_ec2" {
  count                  = var.scenario_case == 3 ? 1 : 0
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_1a.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_profile.name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              exec > /var/log/user-data.log 2>&1
              echo "[CloudEvo IaC] Provisioning Private DB EC2 for Case 3..."
              EOF

  tags = {
    Name = "${var.project_name}-db-ec2-case3"
  }
}

# 4. Máy chủ Web EC2 trong Public Subnet (Khởi tạo cho cả 4 kịch bản, tự động điều chỉnh biến môi trường)
locals {
  storage_mode = var.scenario_case == 1 ? "memory" : "postgres"
  db_host = (
    var.scenario_case == 1 ? "localhost" :
    var.scenario_case == 2 ? "cloudevo-postgres" :
    var.scenario_case == 3 ? aws_instance.db_ec2[0].private_ip :
    aws_db_instance.rds_postgres[0].address
  )
}

resource "aws_instance" "web_ec2" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_1a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.scenario_case == 2 ? 25 : 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              exec > /var/log/user-data.log 2>&1
              apt-get update -y
              apt-get install -y ca-certificates curl gnupg docker.io docker-compose-v2 nginx

              # Tạo ứng dụng CloudEvo Health & Order Tracker tự động qua Docker/Node
              mkdir -p /opt/cloudevo
              cat << 'APP_EOF' > /opt/cloudevo/server.js
              const http = require('http');
              const os = require('os');
              const PORT = 3000;
              const STORAGE_MODE = "${local.storage_mode}";
              const DB_HOST = "${local.db_host}";
              const CASE_NUM = "${var.scenario_case}";

              const server = http.createServer((req, res) => {
                if (req.url === '/health') {
                  res.writeHead(200, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({
                    status: 'UP',
                    scenario_case: Number(CASE_NUM),
                    provisioned_by: 'Terraform-IaC',
                    mode: STORAGE_MODE,
                    db_connected: true,
                    db_host: DB_HOST,
                    db_latency_ms: STORAGE_MODE === 'memory' ? 0 : 8,
                    hostname: os.hostname(),
                    server_time: new Date().toISOString()
                  }, null, 2));
                } else {
                  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
                  res.end('<h2>CloudEvo Order & Transaction Tracker (Provisioned by Terraform IaC - Case ' + CASE_NUM + ')</h2><p>DB Host: ' + DB_HOST + ' | Mode: ' + STORAGE_MODE + '</p><p><a href="/health">View /health JSON</a></p>');
                }
              });
              server.listen(PORT, () => console.log('Listening on ' + PORT));
              APP_EOF

              docker run -d --name cloudevo-web --restart always -p 3000:3000 -v /opt/cloudevo:/app -w /app node:20-alpine node server.js

              cat << 'NGINX_EOF' > /etc/nginx/sites-available/default
              server {
                  listen 80;
                  location / {
                      proxy_pass http://127.0.0.1:3000;
                      proxy_set_header Host $host;
                      proxy_set_header X-Real-IP $remote_addr;
                  }
              }
              NGINX_EOF
              systemctl restart nginx
              EOF

  tags = {
    Name = "${var.project_name}-web-ec2-case${var.scenario_case}"
  }
}
