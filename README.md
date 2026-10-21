# CloudEvo: AWS Architecture Benchmark & DevOps Take-Home Challenge

> **Mục tiêu dự án:** Khảo sát, đo lường thực nghiệm và so sánh chuyên sâu 4 kịch bản kiến trúc trên AWS (Single EC2, Decoupled 2-Tier, Managed RDS) theo 3 trục chỉ số cốt lõi: **Thời gian triển khai (Deployment Time)**, **Chi phí vận hành (FinOps/TCO)** và **Khả năng khắc phục thảm họa (Disaster Recovery - RTO/RPO)**.

---

## Lộ trình Triển khai

- [x] **Ngày 1:** Xây dựng Web App mẫu, thiết kế mạng VPC Multi-AZ & Thực nghiệm Trường hợp 1 (Stateless Single EC2).
- [x] **Ngày 2:** Thực nghiệm Trường hợp 2 (1 Web + 1 DB trên 1 EC2), kiểm thử SPOF & Tự động hóa Backup S3.
- [x] **Ngày 3:** Thực nghiệm Trường hợp 3 (Tách tầng 2 EC2: Web Public + DB Private với Security Group Chaining).
- [x] **Ngày 4:** Thực nghiệm Trường hợp 4 (Web EC2 + Amazon RDS PostgreSQL Multi-AZ & Point-in-Time Recovery).
- [x] **Ngày 5:** Tự động hóa toàn bộ hạ tầng bằng Terraform (IaC) & CI/CD Pipeline (GitHub Actions).
- [x] **Ngày 6:** Hạch toán chi tiết FinOps AWS Pricing Calculator & Thiết kế Sơ đồ kiến trúc.

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

## KẾT QUẢ THỰC NGHIỆM NGÀY 4: TRƯỜNG HỢP 4 (1 WEB TRÊN EC2 + 1 DB TRÊN AMAZON RDS - CLOUD-NATIVE PRODUCTION)

### 1. Kiến trúc Hạ tầng

- **Kiến trúc Chuẩn Cloud-Native 2-Tier (Compute & Managed Database):**
  - **Tầng Web (Compute Tier):** Máy chủ `cloudevo-web-rds-ec2` (`t3.micro`, Ubuntu 22.04 LTS) vận hành tại Public Subnet (`subnet-0914b2264a767ee33`), sở hữu Public IPv4 `13.212.204.91`. Triển khai cụm container bằng Docker Compose gồm Nginx Reverse Proxy (cổng 80) chuyển tiếp lưu lượng vào Node.js Web App (cổng 3000, Hostname `e304be23ed60`).
  - **Tầng Cơ sở dữ liệu (Managed Data Tier):** Dịch vụ quản trị **Amazon RDS for PostgreSQL 16.10** (`cloudevo-rds-postgres`, `db.t4g.micro` - 2 vCPU Graviton2, 1 GiB RAM), lưu trữ trên khối đĩa 20 GiB `gp3` (3.000 IOPS, 125 MiB/s) kèm kích hoạt mã hóa đĩa tĩnh qua AWS KMS (`aws/rds`). Cơ sở dữ liệu được khởi tạo tên `cloudevo_db` với người dùng quản trị `cloudevo`.
- **Phân tách Vùng mạng & Bảo mật Chiều sâu:**
  - Khởi tạo **DB Subnet Group** (`cloudevo-db-subnet-group`) bao trùm 2 Private Subnets trải rộng trên 2 Availability Zones độc lập: `ap-southeast-1a` (`10.0.11.0/24`) và `ap-southeast-1b` (`10.0.12.0/24`), cô lập hoàn toàn cơ sở dữ liệu (`Public access: No`).
  - **Security Group Chaining:** Nhóm bảo mật `cloudevo-db-sg` (`sg-07212bbabd8d70f2c`) khóa chặt cổng 5432, chỉ chấp nhận kết nối từ nguồn duy nhất là ID nhóm bảo mật của máy chủ Web `cloudevo-web-sg` (`sg-03c49016a8a6f5ecd`).
- **Cơ chế Phục hồi Kết nối Tự động (Connection Resiliency):**
  - Web App giao tiếp với cơ sở dữ liệu qua DNS Endpoint: `cloudevo-rds-postgres.c3im66o0wo30.ap-southeast-1.rds.amazonaws.com`.
  - Cấu hình Connection Pool (`connectionTimeoutMillis: 2000`) cho phép ứng dụng duy trì kết nối bền bỉ, phản hồi mã chuẩn `HTTP 503` khi DB gián đoạn và tự động khôi phục luồng xử lý ngay khi RDS khả dụng mà không cần khởi động lại máy chủ Web.
- **Chiến lược Sao lưu Dữ liệu Tự động (Automated Backups & PITR):**
  - Kích hoạt tính năng **Automated Backups** lưu giữ bản ghi transaction logs liên tục, hỗ trợ khả năng khôi phục dữ liệu theo thời điểm (**Point-in-Time Recovery - PITR**) về bất kỳ giây nào trong quá khứ với RPO dưới 5 phút.

---

### 2. Số liệu Đo lường Thực nghiệm

| Chỉ số Đánh giá                       | Phương pháp Kiểm thử                           | Kết quả Thực tế                                                   | Đánh giá Kỹ thuật (DevOps Insight)                                                                                                                                                                                                |
| :------------------------------------ | :--------------------------------------------- | :---------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Thời gian khởi tạo**                | Triển khai thủ công (ClickOps)                 | **~45.0 phút**                                                    | Cấu hình DB Subnet Group, thiết lập hàng chục tùy chọn thông số RDS Console, chờ cấp phát và SSH vào EC2 dựng Web.                                                                                                                |
| **Thời gian khởi tạo**                | Tự động hóa qua RDS & User Data                | **8 phút 30 giây** _(RDS)_ + **2 phút 30 giây** _(Web)_           | Tổng thời gian dựng hoàn chỉnh chỉ mất **~11.0 phút**, **rút ngắn 75.5%** thời gian bàn giao so với ClickOps.                                                                                                                     |
| **Độ trễ Mạng Nội bộ**                | Kết nối Web EC2 $\rightarrow$ RDS Endpoint     | **2ms – 28ms**                                                    | Truy vấn qua endpoint `/health`: kết nối nội bộ VPC tới RDS DNS Endpoint đạt độ ổn định cao và độ trễ cực thấp.                                                                                                                   |
| **Kiểm thử Gián đoạn DB (Test 4A)**   | Kích hoạt RDS Reboot & Đo bằng `dr_monitor.py` | Gián đoạn **11.46 giây** (10 chu kỳ ping lỗi `HTTP 503`)          | Bắt lỗi chính xác: Tầng Web độc lập trả HTTP 503. Kết nối tự phục hồi qua Connection Pool sau 11.46s; Hostname giữ nguyên `e304be23ed60`. **RPO = 0 byte**: Toàn bộ dữ liệu đơn hàng `#401` ($1,250.00) được bảo toàn nguyên vẹn. |
| **Phục hồi theo Thời điểm (Test 4B)** | Khôi phục PITR (`Latest restorable time`)      | Khởi tạo thành công cụm `cloudevo-rds-pitr-restore`               | **RPO < 5 phút**: Tận dụng Transaction Logs tự động đẩy lên S3. Khôi phục độc lập sang instance mới mà không làm gián đoạn cụm Database đang chạy chính. RTO cấp phát máy phục hồi ~8–10 phút.                                    |
| **Chi phí ước tính / Tháng**          | Region Singapore (`ap-southeast-1`)            | **~$29.50 / tháng** _(Single-AZ)_<br>_~$46.00 / tháng (Multi-AZ)_ | 1 EC2 `t3.micro` ($7.59) + 20GB gp3 ($1.92) + 1 RDS `db.t4g.micro` ($14.60) + 20GB RDS gp3 ($2.30) + 1 Public IPv4 ($3.65) + Automated Backup (Miễn phí).                                                                         |

---

### 3. Phân tích Ưu nhược điểm Kỹ thuật

- **Ưu điểm vượt trội so với DB tự quản trị trên EC2 (Trường hợp 2 & 3):**
  - **Triệt tiêu gánh nặng vận hành (Zero OS Maintenance):** AWS tự động đảm nhiệm việc vá lỗi hệ điều hành (OS patching), bảo trì phần cứng và cập nhật bản vá bảo mật cơ sở dữ liệu.
  - **Khôi phục thảm họa đỉnh cao (Disaster Recovery):** Cơ chế Point-in-Time Recovery (PITR) cho phép phục hồi sau các sự cố phá hoại dữ liệu logic (xóa nhầm bảng) với sai lệch dữ liệu cực thấp (RPO < 5 phút), vượt trội hơn cơ chế Cronjob định kỳ 1 giờ ở Case 2 và Case 3.
  - **Khả năng mở rộng & Độ sẵn sàng cao:** Dễ dàng nâng cấp kích thước instance (Vertical Scaling) hoặc chuyển đổi sang cấu hình Multi-AZ chỉ với một cú nhấp chuột/thay đổi biến cấu hình mà không làm gián đoạn cấu trúc mạng.
- **Hạn chế & Rào cản Kỹ thuật (FinOps Trade-offs):**
  - **Chi phí vận hành tăng:** Chi phí hàng tháng ở cấu hình Single-AZ ($29.50) cao hơn ~23% so với Case 3 ($24.00) và cao gấp đôi Case 2 ($14.37); khi bật Multi-AZ ($46.00), chi phí tăng hơn gấp 3 lần.
  - **Thời gian cấp phát ban đầu:** Quá trình khởi tạo máy chủ RDS cần thời gian cấu hình phần cứng độc lập (~8.5 phút), lâu hơn việc khởi tạo một máy chủ EC2 thông thường.

---

### 4. Hướng dẫn Khởi chạy Cục bộ & Triển khai Trường hợp 4

```bash
# 1. Di chuyển vào thư mục kịch bản Case 4
cd scenarios/case4-ec2-web-rds

# 2. Cấu hình RDS Endpoint vào biến môi trường trong file setup_web_rds.sh
# Thay thế giá trị RDS_ENDPOINT="YOUR_RDS_ENDPOINT_HERE"

# 3. Chạy script kiểm thử chuyển đổi dự phòng & giám sát sức khỏe RDS
bash rds_failover_test.sh

# 4. Kiểm tra sức khỏe kết nối giữa Web EC2 và Amazon RDS
curl http://localhost/health
```

---

## KẾT QUẢ THỰC NGHIỆM NGÀY 5: TỰ ĐỘNG HÓA HẠ TẦNG BẰNG TERRAFORM (IaC) & PIPELINE CI/CD (GITHUB ACTIONS)

### 1. Kiến trúc Mã nguồn Terraform & Pipeline CI/CD

- **Hạ tầng dưới dạng Mã Đa Kịch Bản (Multi-Scenario Infrastructure as Code):**
  - Toàn bộ tài nguyên của cả 4 trường hợp được tham số hóa và hợp nhất trong thư mục [`terraform/`](./terraform/) gồm 7 tệp cấu hình chuẩn module:
    - `main.tf`: Khai báo AWS Provider tại Region Singapore (`ap-southeast-1`), gắn nhãn tài nguyên mặc định (`default_tags`) và tự động tra cứu AMI Ubuntu 22.04 LTS chính thức mới nhất từ Canonical (`data.aws_ami`).
    - `variables.tf`: Quản trị biến tập trung; biến điều khiển cốt lõi `scenario_case` (nhận giá trị từ `1` đến `4`) cho phép kích hoạt chính xác kiến trúc mong muốn chỉ bằng một tham số duy nhất.
    - `vpc.tf`: Khởi tạo mạng `cloudevo-vpc` (`10.0.0.0/16`), 2 Public Subnets và 2 Private Subnets trải trên 2 AZs (`ap-southeast-1a`, `ap-southeast-1b`), kèm **Gateway VPC Endpoint kết nối S3 nội bộ miễn phí** (triệt tiêu chi phí NAT Gateway).
    - `security_groups.tf`: Thiết lập bảo mật đa tầng; nhóm bảo mật `web-sg` mở cổng 80/22 và `db-sg` áp dụng cơ chế **Security Group Chaining** (chỉ cho phép cổng PostgreSQL 5432 và SSH 22 xuất phát từ `web-sg`).
    - `compute_ec2.tf`: Khởi tạo IAM Role & Instance Profile theo nguyên tắc Least Privilege để sao lưu S3, tự động phân bổ máy chủ `web-ec2` tại Public Subnet và máy chủ `db-ec2` tại Private Subnet (chỉ kích hoạt ở Case 3).
    - `rds.tf`: Tự động khởi tạo DB Subnet Group cô lập trên 2 AZ và triển khai cơ sở dữ liệu quản trị **Amazon RDS for PostgreSQL 16** (`db.t4g.micro`, ổ cứng `gp3` mã hóa KMS tĩnh) khi kích hoạt Case 4.
    - `outputs.tf`: Tự động trích xuất thông tin hạ tầng sau khi triển khai: VPC ID, IP Public Web, URL kiểm tra sức khỏe `/health` và Endpoint kết nối Database.
- **Đường ống Tự động hóa CI/CD khép kín (GitHub Actions):**
  - Tệp cấu hình [`.github/workflows/deploy.yml`](./.github/workflows/deploy.yml) tự động kích hoạt mỗi khi có thao tác `git push` hoặc `pull_request` vào nhánh chính (`main`/`master`), bao gồm 2 Jobs vận hành song song:
    1. **Job `build-and-test-app` (DevSecOps & Verification):** Tự động đóng gói mã nguồn thành Docker Image, khởi chạy container kiểm thử (Smoke Test) gọi trực tiếp vào endpoint `/health` xác nhận trạng thái phản hồi `HTTP 200` (`status: UP`), sau đó đóng gói và xuất bản Image lên **GitHub Container Registry (GHCR)**.
    2. **Job `terraform-iac-validate` (IaC Governance):** Tự động kiểm tra chuẩn định dạng mã (`terraform fmt -check`), nạp cấu hình không cần backend (`terraform init -backend=false`) và xác thực tính toàn vẹn cú pháp của toàn bộ tệp Terraform (`terraform validate`).

---

### 2. Số liệu Đo lường Thực nghiệm: Tốc độ Bàn giao Hạ tầng

Bảng đối chiếu toàn diện thời gian bàn giao dịch vụ trên cả 4 kịch bản kiến trúc:

| Kịch Bản Kiến Trúc                      | Làm Tay (ClickOps)   | Tự Động Bán Phần (EC2 User Data) | Tự Động Toàn Trình (Terraform IaC) | Mức Rút Ngắn Thời Gian (Tối ưu hóa DevOps)                                                            |
| :-------------------------------------- | :------------------- | :------------------------------- | :--------------------------------- | :---------------------------------------------------------------------------------------------------- |
| **Trường hợp 1 (Stateless Single EC2)** | **20 phút** (1.200s) | **2 phút 48s** (168s)            | **~1 phút 45s** (105s)             | **Rút ngắn 91.2%** thời gian bàn giao; tự động hóa 100% từ VPC đến Web App.                           |
| **Trường hợp 2 (Monolith 1 EC2)**       | **35 phút** (2.100s) | **3 phút 15s** (195s)            | **~2 phút 05s** (125s)             | **Rút ngắn 94.0%** thời gian; tự cấu hình IAM Role, S3 Backup Bucket và Docker Compose.               |
| **Trường hợp 3 (Decoupled 2 EC2)**      | **50 phút** (3.000s) | **~5 phút 00s** (300s)           | **~2 phút 20s** (140s)             | **Rút ngắn 95.3%** thời gian; khởi tạo song song 2 máy chủ trên 2 Subnet kèm Security Group Chaining. |
| **Trường hợp 4 (Web EC2 + Amazon RDS)** | **45 phút** (2.700s) | **~11 phút 00s** (660s)          | **~9 phút 15s** (555s)             | **Rút ngắn 79.4%** thời gian; 100% Hands-free cấp phát DB Subnet Group Multi-AZ và RDS PostgreSQL.    |

- **Quản trị Thu hồi Tài nguyên FinOps (`terraform destroy`):**
  - Chỉ với 1 câu lệnh duy nhất, toàn bộ tài nguyên trên AWS (VPC, Subnets, Route Tables, Internet Gateway, Security Groups, EC2, EBS Volumes, RDS Instance) được giải phóng triệt để theo đúng thứ tự phụ thuộc ngược trong vòng **~1 phút** (với TH1–TH3) và **~4 phút** (với TH4).
  - **Hiệu quả FinOps:** Loại bỏ 100% nguy cơ rò rỉ chi phí từ các tài nguyên ngầm bị bỏ quên (như ổ đĩa EBS mồ côi, địa chỉ Public IPv4 tĩnh $0.005/giờ hay RDS instance nhàn rỗi), bảo toàn ngân sách vận hành ở mức $0.00 ngoài khung giờ kiểm thử.

---

### 3. Phân tích Ưu nhược điểm Kỹ thuật

- **Ưu điểm vượt trội của Infrastructure as Code (IaC) & CI/CD:**
  - **Tính Nhất Quán & Bất Biến (Idempotency):** Xóa bỏ hoàn toàn hiện tượng cấu hình lệch lạc giữa các môi trường (Configuration Drift) và rủi ro gõ sai tham số thủ công của con người.
  - **Tái Lập Môi Trường Tức Thì (Disaster Recovery Support):** Cho phép dựng lại toàn bộ trung tâm dữ liệu ảo trên bất kỳ Region AWS nào khác trong vòng chưa đầy 10 phút khi xảy ra thảm họa diện rộng.
  - **Dịch Chuyển Kiểm Thử Về Sớm (Shift-Left Testing):** Pipeline GitHub Actions bắt lỗi cú pháp, kiểm tra chuẩn định dạng và smoke test logic ứng dụng ngay từ khi lập trình viên tạo Pull Request, ngăn chặn lỗi vỡ hạ tầng trước khi triển khai thực tế.
- **Thách thức Quản trị Cần Kiểm Soát (Production Considerations):**
  - **Bảo Mật State File:** Tệp `terraform.tfstate` chứa thông tin nhạy cảm (như mật khẩu Database, tài nguyên ARN); trong môi trường Production cần lưu trữ bảo mật trên Amazon S3 có kích hoạt mã hóa SSE-KMS kết hợp DynamoDB để khóa trạng thái (State Locking).
  - **Kiểm Soát Biến Động Chi Phí:** Cần tích hợp các công cụ phân tích chi phí tự động (Infracost) vào luồng CI/CD để dự báo chênh lệch hóa đơn AWS trước khi chạy `terraform apply`.

---

### 4. Hướng dẫn Khởi chạy Hạ tầng bằng Terraform

```bash
# 1. Di chuyển vào thư mục terraform
cd terraform

# 2. Khởi tạo Terraform và tải AWS Provider
terraform init

# 3. Kiểm tra định dạng và tính hợp lệ của mã nguồn
terraform fmt -check
terraform validate

# 4. Triển khai kiến trúc tùy chọn (Ví dụ: Kịch bản 1 Stateless hoặc Kịch bản 4 RDS)
# Dựng Kịch bản 1 (Siêu tốc ~1m45s):
terraform apply -var="scenario_case=1" -auto-approve

# Hoặc dựng Kịch bản 4 Cloud-Native (Full Web + Managed RDS):
terraform apply -var="scenario_case=4" -auto-approve

# 5. Kiểm tra kết quả qua Output URL
curl $(terraform output -raw health_check_url)

# 6. Thu hồi toàn bộ tài nguyên sau khi đo kiểm xong (FinOps Cleanup)
terraform destroy -auto-approve
```
