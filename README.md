# CloudEvo: AWS Architecture Benchmark & DevOps Take-Home Challenge

> **Mục tiêu dự án:** Khảo sát, đo lường thực nghiệm và so sánh chuyên sâu 4 kịch bản kiến trúc trên AWS (Single EC2, Decoupled 2-Tier, Managed RDS) theo 3 trục chỉ số cốt lõi: **Thời gian triển khai (Deployment Time)**, **Chi phí vận hành (FinOps/TCO)** và **Khả năng khắc phục thảm họa (Disaster Recovery - RTO/RPO)**.

---

## Lộ trình Triển khai (7-Day Sprint)

- [x] **Ngày 1:** Xây dựng Web App mẫu, thiết kế mạng VPC Multi-AZ & Thực nghiệm Trường hợp 1 (Stateless Single EC2).
- [ ] **Ngày 2:** Thực nghiệm Trường hợp 2 (1 Web + 1 DB trên 1 EC2), kiểm thử SPOF & Tự động hóa Backup S3.
- [ ] **Ngày 3:** Thực nghiệm Trường hợp 3 (Tách tầng 2 EC2: Web Public + DB Private với Security Group Chaining).
- [ ] **Ngày 4:** Thực nghiệm Trường hợp 4 (Web EC2 + Amazon RDS PostgreSQL Multi-AZ & Point-in-Time Recovery).
- [ ] **Ngày 5:** Tự động hóa toàn bộ hạ tầng bằng Terraform (IaC) & CI/CD Pipeline (GitHub Actions).
- [ ] **Ngày 6:** Hạch toán chi tiết FinOps AWS Pricing Calculator & Thiết kế Sơ đồ kiến trúc.
- [ ] **Ngày 7:** Tổng kết Báo cáo Kỹ thuật, hoàn thiện Portfolio & Kịch bản thuyết trình bảo vệ.

---

## KẾT QUẢ THỰC NGHIỆM NGÀY 1: TRƯỜNG HỢP 1 (STATELESS SINGLE EC2)

### 1. Kiến trúc Hạ tầng (Architecture Overview)

- **VPC Mạng chuẩn Production:**
  - VPC CIDR `10.0.0.0/16` tại Region Singapore (`ap-southeast-1`).
  - Phân bổ 2 Public Subnets (`10.0.1.0/24`, `10.0.2.0/24`) và 2 Private Subnets (`10.0.11.0/24`, `10.0.12.0/24`) trên 2 Availability Zones (`ap-southeast-1a`, `ap-southeast-1b`).
  - Cổng Internet Gateway (`cloudevo-igw`) gắn với Public Route Table.
- **Bảo mật Mạng (Security Group):** `cloudevo-web-sg` chỉ mở Port 80 (HTTP) cho người dùng cuối và Port 22 (SSH) để quản trị.
- **Ứng dụng Web:** Node.js Express đứng sau Nginx Reverse Proxy (Port 80 -> Port 3000), tích hợp Endpoint giám sát `/health`.

---

### 2. Số liệu Đo lường Thực nghiệm (Empirical Benchmark)

| Chỉ số Đánh giá              | Phương pháp Triển khai              | Kết quả Thực tế             | Đánh giá Kỹ thuật (DevOps Insight)                                                        |
| :--------------------------- | :---------------------------------- | :-------------------------- | :---------------------------------------------------------------------------------------- |
| **Thời gian khởi tạo**       | ClickOps thủ công qua SSH           | **20 phút**                 | Mất nhiều thời gian gõ lệnh cài Docker, build image và cấu hình file.                     |
| **Thời gian khởi tạo**       | Tự động qua EC2 User Data           | **2.8 phút (~170s)**        | **Tối ưu hóa ~86%** thời gian triển khai, loại bỏ hoàn toàn sai sót do con người.         |
| **Thời gian chết (RTO)**     | Giả lập Terminate & Boot lại        | **449.48 giây (~7.5 phút)** | Đo bằng `dr_monitor.py` (150 chu kỳ ping lỗi). Máy mới tự động khôi phục hoàn chỉnh.      |
| **Mất mát dữ liệu (RPO)**    | Sự cố sập máy chủ                   | **N/A (Reset 100%)**        | Chế độ in-memory: toàn bộ dữ liệu trên RAM biến mất khi đổi Hostname sang `363732ec3ca3`. |
| **Chi phí ước tính / Tháng** | Region Singapore (`ap-southeast-1`) | **~$13.16 / tháng**         | 1 EC2 `t3.micro` ($7.59) + 20GB EBS `gp3` ($1.92) + 1 Public IPv4 ($3.65).                |

---

### 3. Bằng chứng Thực nghiệm (Artifacts & Logs)

Toàn bộ ảnh chụp màn hình chứng minh quá trình đo đạc được lưu trữ trong thư mục [`docs/`](./docs/):

- **Sơ đồ VPC Resource Map:** [`docs/01-vpc-resource-map.png`](./docs/01-vpc-resource-map.png)
- **Cấu hình Security Group:** [`docs/02-web-security-group.png`](./docs/02-web-security-group.png)
- **Giao diện Web App hoạt động:** [`docs/03-case1-web-ui.png`](./docs/03-case1-web-ui.png)
- **Endpoint Health Check:** [`docs/04-case1-health-check.png`](./docs/04-case1-health-check.png)
- **Log phát hiện sự cố (Chaos test):** [`docs/05-case1-rto-incident.png`](./docs/05-case1-rto-incident.png)
- **Khôi phục thành công với Hostname mới:** [`docs/06-case1-rto-recovered.png`](./docs/06-case1-rto-recovered.png)
- **Cấu hình Bootstrap User Data:** [`docs/07-case1-user-data.png`](./docs/07-case1-user-data.png) -[Xem Báo Cáo Kỹ Thuật Ngày 1 (PDF)](./docs/DAY1_BENCHMARK_REPORT.pdf)

---

## 🛠 Hướng dẫn Khởi chạy Cục bộ (Local Run via Docker)

Bất kỳ ai clone repository này về đều có thể chạy thử nghiệm Web App ngay tại máy cá nhân:

```bash
# 1. Di chuyển vào thư mục kịch bản Case 1
cd scenarios/case1-single-ec2-web

# 2. Khởi chạy bằng Docker Compose
docker compose up -d --build

# 3. Kiểm tra trạng thái
curl http://localhost/health
```
