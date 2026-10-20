# CloudEvo: AWS Architecture Benchmark & DevOps Take-Home Challenge

> **Mục tiêu dự án:** Khảo sát, đo lường thực nghiệm và so sánh chuyên sâu 4 kịch bản kiến trúc trên AWS (Single EC2, Decoupled 2-Tier, Managed RDS) theo 3 trục chỉ số cốt lõi: **Thời gian triển khai (Deployment Time)**, **Chi phí vận hành (FinOps/TCO)** và **Khả năng khắc phục thảm họa (Disaster Recovery - RTO/RPO)**.

---

## Lộ trình Triển khai

- [x] **Ngày 1:** Xây dựng Web App mẫu, thiết kế mạng VPC Multi-AZ & Thực nghiệm Trường hợp 1 (Stateless Single EC2).
- [x] **Ngày 2:** Thực nghiệm Trường hợp 2 (1 Web + 1 DB trên 1 EC2), kiểm thử SPOF & Tự động hóa Backup S3.
- [x] **Ngày 3:** Thực nghiệm Trường hợp 3 (Tách tầng 2 EC2: Web Public + DB Private với Security Group Chaining).
- [ ] **Ngày 4:** Thực nghiệm Trường hợp 4 (Web EC2 + Amazon RDS PostgreSQL Multi-AZ & Point-in-Time Recovery).
- [ ] **Ngày 5:** Tự động hóa toàn bộ hạ tầng bằng Terraform (IaC) & CI/CD Pipeline (GitHub Actions).
- [ ] **Ngày 6:** Hạch toán chi tiết FinOps AWS Pricing Calculator & Thiết kế Sơ đồ kiến trúc.
- [ ] **Ngày 7:** Tổng kết Báo cáo Kỹ thuật, hoàn thiện Portfolio & Kịch bản thuyết trình bảo vệ.

---

## KẾT QUẢ THỰC NGHIỆM NGÀY 1: TRƯỜNG HỢP 1(Hosting 1 web application on single EC2)

### 1. Kiến trúc Hạ tầng

- **VPC Mạng chuẩn Production:**
  - VPC CIDR `10.0.0.0/16` tại Region Singapore (`ap-southeast-1`).
  - Phân bổ 2 Public Subnets (`10.0.1.0/24`, `10.0.2.0/24`) và 2 Private Subnets (`10.0.11.0/24`, `10.0.12.0/24`) trên 2 Availability Zones (`ap-southeast-1a`, `ap-southeast-1b`).
  - Cổng Internet Gateway (`cloudevo-igw`) gắn với Public Route Table.
- **Bảo mật Mạng (Security Group):** `cloudevo-web-sg` chỉ mở Port 80 (HTTP) cho người dùng cuối và Port 22 (SSH) để quản trị.
- **Ứng dụng Web:** Node.js Express đứng sau Nginx Reverse Proxy (Port 80 -> Port 3000), tích hợp Endpoint giám sát `/health`.

---

### 2. Số liệu Đo lường Thực nghiệm

| Chỉ số Đánh giá              | Phương pháp Triển khai              | Kết quả Thực tế             | Đánh giá Kỹ thuật (DevOps Insight)                                                        |
| :--------------------------- | :---------------------------------- | :-------------------------- | :---------------------------------------------------------------------------------------- |
| **Thời gian khởi tạo**       | ClickOps thủ công qua SSH           | **20 phút**                 | Mất nhiều thời gian gõ lệnh cài Docker, build image và cấu hình file.                     |
| **Thời gian khởi tạo**       | Tự động qua EC2 User Data           | **2.8 phút (~170s)**        | **Tối ưu hóa ~86%** thời gian triển khai, loại bỏ hoàn toàn sai sót do con người.         |
| **Thời gian chết (RTO)**     | Giả lập Terminate & Boot lại        | **449.48 giây (~7.5 phút)** | Đo bằng `dr_monitor.py` (150 chu kỳ ping lỗi). Máy mới tự động khôi phục hoàn chỉnh.      |
| **Mất mát dữ liệu (RPO)**    | Sự cố sập máy chủ                   | **N/A (Reset 100%)**        | Chế độ in-memory: toàn bộ dữ liệu trên RAM biến mất khi đổi Hostname sang `363732ec3ca3`. |
| **Chi phí ước tính / Tháng** | Region Singapore (`ap-southeast-1`) | **~$13.16 / tháng**         | 1 EC2 `t3.micro` ($7.59) + 20GB EBS `gp3` ($1.92) + 1 Public IPv4 ($3.65).                |

---

### 3. Bằng chứng Thực nghiệm

Toàn bộ ảnh chụp màn hình chứng minh quá trình đo đạc được lưu trữ trong thư mục [`docs/`](./docs/)

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

---

## KẾT QUẢ THỰC NGHIỆM NGÀY 2: TRƯỜNG HỢP 2 (1 WEB + 1 DB TRÊN CÙNG 1 EC2)

### 1. Kiến trúc Hạ tầng

- **Mô hình triển khai All-in-One:**
  - 1 Máy chủ EC2 (`t3.micro`, Ubuntu 22.04 LTS) đặt tại Public Subnet thuộc `cloudevo-vpc` (Region Singapore `ap-southeast-1`).
  - Đóng gói toàn bộ ngăn xếp dịch vụ bằng **Docker Compose** gồm 3 containers:
    - `cloudevo-nginx`: Nginx reverse proxy tiếp nhận traffic cổng 80 chuyển tiếp vào cổng 3000.
    - `cloudevo-web`: Node.js Express API kết nối PostgreSQL qua biến môi trường `STORAGE_MODE=postgres`.
    - `cloudevo-postgres`: Database PostgreSQL 15 Alpine lưu trữ dữ liệu bền vững trên Docker Named Volume `pgdata`.
- **Bảo mật Tối thiểu :** Gán IAM Role `cloudevo-ec2-s3-backup-role` cho EC2, chỉ cho phép thực thi `s3:ListBucket`, `s3:PutObject`, `s3:GetObject` trên đúng bucket `cloudevo-backup-dangth`, tuyệt đối không dùng Root hay Access Key cứng.
- **Chiến lược Bảo vệ Dữ liệu:**
  - Thiết lập Cronjob tự động chạy mỗi 1 giờ (`0 * * * *`) xuất dữ liệu bằng `pg_dump`, nén `.sql.gz` và đồng bộ lên Amazon S3 (`backup_s3.sh`).
  - Tạo bản sao lưu toàn bộ ổ đĩa máy chủ `cloudevo-case2-ebs-snapshot` (Volume gp3 25GB).

---

### 2. Số liệu Đo lường Thực nghiệm

| Chỉ số Đánh giá                      | Phương pháp Kiểm thử                           | Kết quả Thực tế                                   | Đánh giá Kỹ thuật (DevOps Insight)                                                                                                                                                    |
| :----------------------------------- | :--------------------------------------------- | :------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Thời gian khởi tạo**               | Triển khai thủ công (ClickOps)                 | **~35 phút**                                      | Cài Docker, viết Compose, cấu hình PostgreSQL và phân quyền S3 thủ công.                                                                                                              |
| **Thời gian khởi tạo**               | Tự động hóa qua EC2 User Data                  | **3 phút 15 giây (195s)**                         | **Rút ngắn 90.7% thời gian**, tự động hóa toàn bộ việc dựng container, cấu hình IAM CLI và đặt lịch Cronjob.                                                                          |
| **Kiểm thử Nghẽn tài nguyên (SPOF)** | Kịch bản 2A: `stress-ng` CPU/RAM & Treo DB     | Gián đoạn **34.96 giây** (12 chu kỳ ping lỗi)     | Chứng minh điểm nghẽn **Single Point of Failure (SPOF)**: Khi PostgreSQL ngốn CPU/RAM hoặc bị khóa, toàn bộ Web App bị treo và trả lỗi theo (`timed out`).                            |
| **Thời gian Phục hồi (RTO)**         | Kịch bản 2B: Sập cụm máy chủ & Khôi phục từ S3 | **82.49 giây** (28 chu kỳ ping lỗi)               | Đo bằng `dr_monitor.py`. Toàn bộ dữ liệu được nạp lại tự động từ bản sao lưu S3 mới nhất (`latest.sql.gz`) qua script `restore_s3.sh`.                                                |
| **Mất mát Dữ liệu (RPO)**            | So sánh dữ liệu trước và sau khôi phục         | **Mất dữ liệu phát sinh sau lần backup gần nhất** | Giao dịch `#1` (Init) được giữ nguyên vẹn; Giao dịch `#2` (`Order #103 - AFTER Backup`) tạo sau khi chạy backup bị mất hoàn toàn. RPO phụ thuộc trực tiếp vào chu kỳ Cronjob (1 giờ). |
| **Chi phí ước tính / Tháng**         | Region Singapore (`ap-southeast-1`)            | **~$14.37 / tháng**                               | 1 EC2 `t3.micro` ($7.59) + 25GB EBS `gp3` ($2.40) + 1 Public IPv4 ($3.65) + S3/Snapshot Storage (~$0.73).                                                                             |

---

### 3. Phân tích Ưu nhược điểm Kỹ thuật

- **Ưu điểm:**
  - Tối ưu chi phí ban đầu: Tận dụng chung 1 máy chủ EC2 giá rẻ cho cả Web App và Database.
  - Thiết lập đơn giản, độ trễ truy vấn Database cực thấp do kết nối trực tiếp trong mạng nội bộ Docker (`localhost`/Docker network).
- **Nhược điểm & Rủi ro Sản xuất (Production Pitfalls):**
  - **Single Point of Failure (SPOF):** Sự cố tại tầng cơ sở dữ liệu sẽ kéo theo toàn bộ giao diện người dùng bị gián đoạn.
  - **Tranh chấp tài nguyên:** Không thể mở rộng độc lập (Scale Web riêng hoặc Scale DB riêng); khi tải tăng cao, bộ nhớ đệm của PostgreSQL dễ dẫn đến lỗi tràn RAM (OOM Killer).
  - **RPO cao:** Cơ chế Backup theo chu kỳ định kỳ (Cronjob) luôn tiềm ẩn nguy cơ mất mát dữ liệu nghiệp vụ của khách hàng giữa 2 lần chạy.

---

### 4. Hướng dẫn Chạy Cục bộ Trường hợp 2 (Local Run)

```bash
# 1. Di chuyển vào thư mục kịch bản Case 2
cd scenarios/case2-single-ec2-web-db

# 2. Khởi chạy toàn bộ hệ thống Web + PostgreSQL + Nginx
docker compose up -d --build

# 3. Kiểm tra trạng thái ứng dụng và cơ sở dữ liệu
curl http://localhost/health

# 4. Chạy thử nghiệm script sao lưu dữ liệu lên S3
bash backup_s3.sh
```

---

## KẾT QUẢ THỰC NGHIỆM NGÀY 3: TRƯỜNG HỢP 3 (1 WEB TRÊN EC2 + 1 DB TRÊN EC2 RIÊNG BIỆT - DECOUPLED 2-TIER)

### 1. Kiến trúc Hạ tầng

- **Kiến trúc Tách tầng Độc lập (Decoupled 2-Tier):**
  - **Tầng Web (Compute Tier):** Máy chủ `cloudevo-web-ec2` (`i-035bc597ce46ffb41`, `t3.micro`) đặt tại Public Subnet (`subnet-0914b2264a767ee33`), sở hữu Public IPv4 `13.229.225.174` và Private IP `10.0.1.183`. Đóng gói ứng dụng gồm Nginx Reverse Proxy (cổng 80) chuyển tiếp vào Node.js Express (cổng 3000).
  - **Tầng Cơ sở dữ liệu (Data Tier):** Máy chủ `cloudevo-db-ec2` (`i-0e14eeeabd149cc1f`, `t3.micro`) đặt cô lập tại Private Subnet (`subnet-07a286c5fddc36e80`), chỉ sử dụng Private IPv4 `10.0.11.246`, không gắn Public IP. Cài đặt trực tiếp PostgreSQL 15, lắng nghe cổng nội bộ 5432 (`listen_addresses = '*'`) và xác thực qua dải mạng VPC (`scram-sha-256`).
- **Bảo mật Chiều sâu (Security Group Chaining):**
  - Nhóm bảo mật `cloudevo-db-sg` (`sg-07212bbabd8d70f2c`) áp dụng nguyên tắc tối thiểu hóa bề mặt tấn công: **chỉ mở Inbound cổng 5432 (PostgreSQL) và cổng 22 (SSH)** với Source duy nhất là ID của nhóm bảo mật Web `cloudevo-web-sg` (`sg-03c49016a8a6f5ecd`). Tuyệt đối không phơi nhiễm cổng Database ra Internet công cộng.
  - Máy chủ `cloudevo-web-ec2` đồng thời đóng vai trò làm Bastion Host (Jump Server) để kỹ sư truy cập SSH quản trị máy chủ DB nội bộ.
- **Tối ưu Chi phí Mạng (FinOps Network Optimization):**
  - Tầng DB tại Private Subnet kết nối và đẩy các bản sao lưu `backup_s3.sh` trực tiếp lên Amazon S3 (`cloudevo-backup-dangth`) thông qua **Gateway VPC Endpoint** (`vpce-...`), giúp loại bỏ hoàn toàn chi phí đắt đỏ của NAT Gateway (~$43/tháng).

---

### 2. Số liệu Đo lường Thực nghiệm

| Chỉ số Đánh giá                     | Phương pháp Kiểm thử                 | Kết quả Thực tế                                           | Đánh giá Kỹ thuật (DevOps Insight)                                                                                                                                              |
| :---------------------------------- | :----------------------------------- | :-------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Thời gian khởi tạo**              | Triển khai thủ công (ClickOps)       | **~50.0 phút**                                            | Khởi tạo 2 EC2 trên 2 Subnet, cấu hình SSH Bastion/Key, cài đặt PostgreSQL, tinh chỉnh `pg_hba.conf` và liên kết Security Group thủ công.                                       |
| **Thời gian khởi tạo**              | Tự động hóa qua EC2 User Data        | **2 phút 30 giây (150s)**                                 | User Data tự động tải gói `postgresql` từ Ubuntu repo và cấu hình DB EC2; tổng thời gian dựng cả cụm 2 máy chỉ mất **~5 phút** (**Rút ngắn 90.0%** thời gian).                  |
| **Độ trễ Mạng Nội bộ**              | Kết nối Web EC2 $\rightarrow$ DB EC2 | **12ms**                                                  | Kiểm tra qua endpoint `/health`: kết nối nội bộ VPC qua Private IP `10.0.11.246` đạt độ ổn định và bảo mật cao.                                                                 |
| **Kiểm thử Sập tầng Web (Test 3A)** | Sập Web EC2 / Khởi động lại dịch vụ  | Gián đoạn **86.05 giây** (29 chu kỳ ping lỗi `timed out`) | Hostname chuyển từ `c508d5e66ff3` sang `f9d769cd28a0`. **RPO = 0 byte**: Tầng Database hoàn toàn độc lập, bảo toàn 100% dữ liệu giao dịch (`Order #201 - $550.00`).             |
| **Kiểm thử Sập tầng DB (Test 3B)**  | Dừng Database & Phục hồi từ S3       | Gián đoạn **44.07 giây** (39 chu kỳ ping lỗi `HTTP 503`)  | Bắt lỗi chính xác: Web App vẫn sống độc lập và trả về HTTP 503 khi mất DB. Dữ liệu nạp lại thành công từ S3 qua `restore_s3.sh`. RPO tương đương chu kỳ Cronjob backup (1 giờ). |
| **Chi phí ước tính / Tháng**        | Region Singapore (`ap-southeast-1`)  | **~$24.00 / tháng**                                       | 2 x EC2 `t3.micro` ($15.18) + 2 x 20GB EBS `gp3` ($3.84) + 1 Public IPv4 ($3.65) + S3/Snapshot (~$1.33).                                                                        |

---

### 3. Phân tích Ưu nhược điểm Kỹ thuật

- **Ưu điểm so với Trường hợp 2 (Monolith):**
  - **Triệt tiêu Single Point of Failure (SPOF):** Sự cố quá tải hoặc sập tại một tầng không kéo theo tầng còn lại; tầng Web sập hoàn toàn không gây mất mát dù chỉ 1 byte dữ liệu ở Database.
  - **Bảo mật chuẩn Doanh nghiệp:** Database được cô lập trong Private Subnet và bảo vệ 2 lớp nhờ Security Group Chaining, ngăn chặn nguy cơ xâm nhập trực tiếp từ Internet.
  - **Độc lập Tài nguyên & Khả năng Scale:** CPU/RAM giữa Web và DB không còn tranh chấp; có thể nâng cấp cấu hình hoặc mở rộng máy chủ Web (Auto Scaling) mà không ảnh hưởng tới DB.
- **Hạn chế & Rủi ro Quản trị (Unmanaged Database Trade-offs):**
  - **Chi phí vận hành tăng:** Chi phí hàng tháng tăng ~65% so với Trường hợp 2 ($24.00 so với $14.50) do phải duy trì 2 máy chủ EC2 và 2 khối EBS.
  - **Gánh nặng Tự quản trị (Operational Overhead):** Vẫn là cơ sở dữ liệu tự dựng (Self-managed DB) trên EC2, đội ngũ kỹ sư phải tự cấu hình sao lưu, tự vá lỗi hệ điều hành, tự xử lý mở rộng dung lượng ổ đĩa và không có cơ chế Multi-AZ tự động chuyển đổi dự phòng (Automatic Failover) như Managed Service (Amazon RDS).

---

### 4. Hướng dẫn Khởi chạy Cục bộ & Triển khai Trường hợp 3

```bash
# 1. Di chuyển vào thư mục kịch bản Case 3
cd scenarios/case3-two-ec2-web-db

# 2. Cấu hình địa chỉ IP Database nội bộ trong script cài đặt
# Sửa biến DB_PRIVATE_IP="THAY_PRIVATE_IP_DB_EC2_VAO_DAY" trong file setup_web_ec2.sh

# 3. Chạy script cấu hình mạng PostgreSQL và pg_hba.conf trên máy DB
sudo bash pg_hba_config.sh

# 4. Kiểm tra sức khỏe kết nối giữa Web và Private DB
curl http://localhost/health
```
