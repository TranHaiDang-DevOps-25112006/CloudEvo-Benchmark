# 1. Khởi tạo VPC chính (10.0.0.0/16)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# 2. Internet Gateway kết nối ra Internet cho Public Subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# 3. Hệ thống 2 Public Subnets trải trên 2 AZ (ap-southeast-1a & 1b)
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public1-${var.aws_region}a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public2-${var.aws_region}b"
  }
}

# 4. Hệ thống 2 Private Subnets trải trên 2 AZ (ap-southeast-1a & 1b)
resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-subnet-private1-${var.aws_region}a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-subnet-private2-${var.aws_region}b"
  }
}

# 5. Route Table cho Public Subnets (Định tuyến 0.0.0.0/0 qua IGW)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-rtb-public"
  }
}

resource "aws_route_table_association" "public_1a_assoc" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_1b_assoc" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. Route Tables cho Private Subnets (Cô lập Internet hoàn toàn - Zero NAT Gateway FinOps)
resource "aws_route_table" "private_rt_1a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rtb-private1-${var.aws_region}a"
  }
}

resource "aws_route_table" "private_rt_1b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rtb-private2-${var.aws_region}b"
  }
}

resource "aws_route_table_association" "private_1a_assoc" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_rt_1a.id
}

resource "aws_route_table_association" "private_1b_assoc" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_rt_1b.id
}

# 7. S3 Gateway VPC Endpoint (Truyền tải Backup S3 nội bộ miễn phí 100%, không cần NAT Gateway)
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public_rt.id,
    aws_route_table.private_rt_1a.id,
    aws_route_table.private_rt_1b.id
  ]

  tags = {
    Name = "${var.project_name}-vpce-s3"
  }
}
