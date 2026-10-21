# BÁO CÁO KỸ THUẬT NGÀY 6: HẠCH TOÁN CHI PHÍ & MA TRẬN BENCHMARK 4 KIẾN TRÚC AWS

**Dự án:** CloudEvo Benchmark Take-Home Assessment  
**Ứng viên:** Trần Hải Đăng (DevOps Intern Candidate)  
**Region thực nghiệm:** Asia Pacific (Singapore) — `ap-southeast-1`  
**Thời gian tính toán:** 730 giờ / tháng (Vận hành liên tục 24/7)

---

## PHẦN 1: HẠCH TOÁN CHI PHÍ HÀNG THÁNG

### 1.1. Bảng Bóc Tách Chi Phí Chi Tiết Theo Từng Linh Kiện (Region: ap-southeast-1)

| Hạng mục Tài nguyên          | Đơn giá Quy chuẩn (ap-southeast-1)       | TH 1: Single EC2 Stateless | TH 2: Single EC2 Monolith | TH 3: Decoupled 2-Tier EC2 | TH 4A: EC2 + RDS (Single-AZ) | TH 4B: EC2 + RDS (Multi-AZ Prod) |
| :--------------------------- | :--------------------------------------- | :------------------------- | :------------------------ | :------------------------- | :--------------------------- | :------------------------------- |
| **Compute Web (EC2)**        | `t3.micro` (2 vCPU, 1GB RAM) @ $0.0104/h | $7.59 (1 máy)              | $7.59 (1 máy chung)       | $7.59 (1 máy Public)       | $7.59 (1 máy Public)         | $7.59 (1 máy Public)             |
| **Compute DB**               | EC2 `t3.micro` hoặc RDS `db.t4g.micro`   | $0.00 (In-Memory RAM)      | $0.00 (Chạy chung máy)    | $7.59 (1 máy Private EC2)  | $14.60 (1 RDS Single-AZ)     | $29.20 (2 RDS Multi-AZ Standby)  |
| **EBS Storage (OS/App)**     | `gp3` ($0.096 / GB-tháng)                | $1.92 (20 GB)              | $2.40 (25 GB)             | $3.84 (2 × 20 GB)          | $1.92 (20 GB Web)            | $1.92 (20 GB Web)                |
| **RDS Managed Storage**      | RDS `gp3` ($0.115 / GB-tháng)            | $0.00                      | $0.00                     | $0.00                      | $2.30 (20 GB Single-AZ)      | $4.60 (20 GB Multi-AZ)           |
| **Public IPv4 Address**      | $0.005 / giờ × 730h / địa chỉ            | $3.65 (1 IP Web)           | $3.65 (1 IP Web)          | $3.65 (1 IP Web; DB $0)    | $3.65 (1 IP Web; RDS $0)     | $3.65 (1 IP Web; RDS $0)         |
| **Backup Storage**           | S3 Standard + EBS Snapshot / PITR        | $0.00 (Không lưu trữ)      | ~$0.86 (S3 + 25GB Snap)   | ~$1.33 (S3 + 20GB Snap)    | $0.00 (Miễn phí 20GB PITR)   | $0.00 (Miễn phí 20GB PITR)       |
| **Hạ tầng Mạng & NAT**       | VPC, IGW, S3 Gateway Endpoint            | $0.00 (Không dùng NAT)     | $0.00 (Endpoint $0)       | $0.00 (Endpoint $0)        | $0.00 (DB Subnet Group)      | $0.00 (DB Subnet Group)          |
| **TỔNG CHI PHÍ TCO / THÁNG** | **Tối ưu hóa FinOps Thực tế**            | **~$13.16 / tháng**        | **~$14.50 / tháng**       | **~$24.00 / tháng**        | **~$29.50 / tháng**          | **~$46.00 / tháng**              |

---

### 1.2. Phân Tích Chi Phí Theo Các Mô Hình Mua

| Kịch bản Kiến trúc         | On-Demand (Mặc định) | 1-Year Savings Plan / RI (Tiết kiệm ~15%) | 3-Year Savings Plan / RI (Tiết kiệm ~25%) | Spot / Hybrid Strategy (Dev/Staging)     | Khuyến nghị Ứng dụng                 |
| :------------------------- | :------------------- | :---------------------------------------- | :---------------------------------------- | :--------------------------------------- | :----------------------------------- |
| **TH 1: Stateless Web**    | **$13.16 / tháng**   | $11.55 / tháng                            | $10.36 / tháng                            | $8.41 / tháng (EC2 Spot)                 | Landing Page, Test POC ngắn hạn      |
| **TH 2: Monolith Web+DB**  | **$14.50 / tháng**   | $12.89 / tháng                            | $11.70 / tháng                            | $9.75 / tháng (EC2 Spot)                 | MVP nội bộ, ứng dụng tra cứu cá nhân |
| **TH 3: Decoupled 2-Tier** | **$24.00 / tháng**   | $20.78 / tháng                            | $18.40 / tháng                            | $15.82 / tháng (Web Spot + DB RI)        | Startup tối ưu ngân sách tự quản trị |
| **TH 4A: RDS Single-AZ**   | **$29.50 / tháng**   | $25.20 / tháng                            | $21.80 / tháng                            | $22.10 / tháng (Web Spot + RDS RI)       | Môi trường Staging / Pre-Production  |
| **TH 4B: RDS Multi-AZ**    | **$46.00 / tháng**   | $39.10 / tháng                            | $33.40 / tháng                            | $34.20 / tháng (Web Spot + RDS Multi-AZ) | **Chuẩn Production Doanh nghiệp**    |

---

## PHẦN 2: MA TRẬN ĐỐI CHIẾU TRẢ LỜI 3 CÂU HỎI KHÁCH HÀNG

### 2.1. Câu hỏi Khách hàng #1: "Host Web App trên AWS mất bao lâu?"

| Phương thức Triển khai             | TH 1: Stateless    | TH 2: Monolith     | TH 3: Decoupled 2-Tier | TH 4: Managed RDS            |
| :--------------------------------- | :----------------- | :----------------- | :--------------------- | :--------------------------- |
| **Dựng Thủ công (ClickOps)**       | 20.0 phút (1.200s) | 35.0 phút (2.100s) | 50.0 phút (3.000s)     | 45.0 phút (2.700s)           |
| **Tự động hóa (User Data Script)** | 2 phút 48s (~168s) | 3 phút 15s (195s)  | ~5 phút 00s (300s)     | ~11 phút 00s (RDS + Script)  |
| **Terraform IaC (Toàn trình)**     | **~1 phút 45s**    | **~2 phút 05s**    | **~2 phút 20s**        | **~9 phút 15s** (Zero-Touch) |
| **Hiệu quả Tối ưu Thời gian**      | **Rút ngắn 91.2%** | **Rút ngắn 94.0%** | **Rút ngắn 95.3%**     | **Rút ngắn 79.4%**           |

---

### 2.2. Câu hỏi Khách hàng #2: "Chi phí vận hành hàng tháng là bao nhiêu?"

- **Trường hợp 1:** **$13.16 / tháng** (Cấu hình tối thiểu cho Web tĩnh/Stateless).
- **Trường hợp 2:** **$14.50 / tháng** (Tiết kiệm nhất cho ứng dụng có Database và Backup S3).
- **Trường hợp 3:** **$24.00 / tháng** (Tách rời tài nguyên, tăng tính bảo mật mạng nội bộ).
- **Trường hợp 4 (Khuyên dùng):** **$29.50 / tháng** (Single-AZ) hoặc **$46.00 / tháng** (Multi-AZ Production chuẩn doanh nghiệp).

---

### 2.3. Câu hỏi Khách hàng #3: "Khi có sự cố, RTO phục hồi mất bao lâu và RPO mất bao nhiêu dữ liệu?"

| Phân tầng Sự cố Thực tế                 | TH 1: Stateless Single EC2                              | TH 2: Monolith Web + DB                                  | TH 3: Decoupled 2-Tier EC2                                          | TH 4: Cloud-Native Managed RDS                                              |
| :-------------------------------------- | :------------------------------------------------------ | :------------------------------------------------------- | :------------------------------------------------------------------ | :-------------------------------------------------------------------------- |
| **1. Tiến trình Web Crash (Container)** | **~5 – 10 giây** (Docker tự khởi động lại)              | **~7 – 10 giây** (Docker tự khởi động lại)               | **~10 – 15 giây** (Docker tự khởi động lại)                         | **~10 – 15 giây** (Docker tự khởi động lại)                                 |
| **2. Quá tải CPU / Tranh chấp DB**      | Không bị ảnh hưởng                                      | **34.96 giây gián đoạn** (Chết chùm do nghẽn CPU/RAM)    | **0s Downtime Web** (Web trả HTTP 503 khi DB nghẽn)                 | **0s Downtime Web** (Web trả HTTP 503 có kiểm soát)                         |
| **3. Gián đoạn Kết nối Database**       | N/A (Không có DB ngoài)                                 | Sập toàn bộ ứng dụng                                     | **44.07 giây** (Restore S3 qua lệnh bash)                           | **11.46 giây** (Connection Pool tự Reconnect)                               |
| **4. Máy chủ EC2 Sập / Hỏng Phần cứng** | **449.48 giây (~7.5 phút)** (Dựng lại máy + nạp script) | **~15 – 30 phút** (Dựng máy + restore file dump S3)      | • Web: **86.05 giây**<br>• DB: **15 – 25 phút** (Snapshot)          | • Web: **86.05 giây**<br>• RDS: **60 – 120 giây** (Multi-AZ Failover)       |
| **5. Mức độ Mất Dữ liệu (RPO)**         | **Mất trắng 100% dữ liệu** (Dữ liệu nằm trên RAM)       | **Mất dữ liệu tới 1 giờ** (Mất đơn hàng #103 sau backup) | • Sập Web: **RPO = 0 byte**<br>• Sập DB: **Tối đa 1 giờ** (S3 dump) | • Lỗi hệ thống: **RPO = 0 byte**<br>• Xóa nhầm dữ liệu: **< 5 phút (PITR)** |
