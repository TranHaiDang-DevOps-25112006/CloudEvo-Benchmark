# 📊 HẠCH TOÁN CHI PHÍ & MA TRẬN BENCHMARK 4 KIẾN TRÚC AWS

> Giá tính theo **on-demand, vùng ap-southeast-1 (Singapore), 730 giờ/tháng, chưa gồm chi phí truyền tải dữ liệu**. Đây là chi phí *tính theo bảng giá công bố*, không phải dữ liệu hóa đơn. Mọi số đo thực nghiệm là kết quả của **một lần chạy**. Nhãn **(ước lượng)** nghĩa là chưa đo trong lab.

## 1. Chi phí hàng tháng

### 1.1 Cơ sở tính giá

- EC2 `t3.micro`: $0.0132/giờ = **$9.64/tháng**. EBS gp3: $0.096/GB-tháng. Public IPv4: $0.005/giờ = **$3.65/tháng** mỗi địa chỉ.
- RDS `db.t4g.micro` (PostgreSQL): $0.025/giờ Single-AZ = **$18.25/tháng**; $0.051/giờ Multi-AZ = **$37.23/tháng**. Lưu trữ RDS gp3: $0.138/GB-tháng (Multi-AZ gấp đôi); dung lượng backup tự động miễn phí tới bằng dung lượng DB.
- S3 và snapshot ở Case 2–3 là ước tính nhỏ (~$0.86 và ~$1.33/tháng).
- Giá EC2, RDS instance và NAT Gateway đã đối chiếu với bảng giá công khai (10/2026). Giá lưu trữ EBS gp3 và RDS gp3 nên được đối chiếu lại bằng AWS Pricing Calculator.

### 1.2 Bảng chi phí chi tiết (USD/tháng)

| Thành phần | Case 1 | Case 2 | Case 3 | Case 4A (RDS Single-AZ) | Case 4B (RDS Multi-AZ, chỉ báo giá) |
|---|---|---|---|---|---|
| Web EC2 `t3.micro` | 9.64 | 9.64 | 9.64 | 9.64 | 9.64 |
| DB compute | 0.00 (RAM) | 0.00 (cùng máy) | 9.64 (EC2 private) | 18.25 | 37.23 |
| Lưu trữ gp3 | 1.92 | 2.40 | 3.84 | 4.68 (1.92 + 2.76) | 7.44 (1.92 + 5.52) |
| Public IPv4 (chỉ Web) | 3.65 | 3.65 | 3.65 | 3.65 | 3.65 |
| Backup / snapshot | 0.00 | ~0.86 | ~1.33 | 0.00 | 0.00 |
| VPC, IGW, S3 Gateway Endpoint | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| **Tổng** | **15.21** | **16.55** | **28.10** | **36.22** | **57.96** |

CloudWatch Alarm (~$0.10 mỗi standard alarm/tháng) và email SNS không nằm trong bảng; tối đa 5 alarm ≈ $0.50/tháng.

### 1.3 Vì sao không dùng NAT Gateway

NAT Gateway ở ap-southeast-1: $0.059/giờ = **$43.07/tháng** (chưa gồm phí xử lý theo GB, và cần thêm một Public IPv4). Thêm một NAT vào Case 3 sẽ đưa chi phí từ $28.10 lên ít nhất $71.17 (+153%). Thiết kế tránh NAT: backup đi qua S3 Gateway Endpoint (không tính phí theo giờ hay theo GB) và DB host chỉ cần Internet một lần lúc khởi tạo.

### 1.4 Ước tính khi cam kết hoặc dùng Spot (chỉ dòng compute — chỉ mang tính tham khảo)

| Dòng compute | On-demand | 1 năm | 3 năm | Spot |
|---|---|---|---|---|
| Web EC2 `t3.micro` | $9.64 | ~$6.94 (Compute Savings Plan, ~28%) | ~$4.63 (~52%) | ~$4.09 (~$0.0056/giờ; có thể bị thu hồi) |
| RDS `db.t4g.micro` (Single-AZ) | $18.25 | ~$14 (Reserved Instance) | ~$11 (Reserved Instance) | Không có |

Mức giảm là giá trị công khai tham khảo cho dòng instance burstable ở ap-southeast-1; hãy kiểm tra lại trước khi cam kết. Thay dòng compute tương ứng trong bảng 1.2 để ra tổng cho từng kịch bản.

## 2. Ma trận so sánh

### 2.1 Thời gian triển khai (một lần chạy)

| Kịch bản | ClickOps | EC2 User Data | Terraform |
|---|---|---|---|
| Case 1 | 20 phút | 2 phút 48s (−86.0%) | ~1 phút 45s (đã đo, ~−91%) |
| Case 2 | 35 phút | 3 phút 15s (−90.7%) | chưa đo |
| Case 3 | 50 phút | ~5 phút (−90.0%) | chưa đo |
| Case 4 | 45 phút | ~11 phút (−75.6%; RDS ~8 phút 30s) | chưa đo |

Thời gian User Data không gồm bước dựng VPC/IAM một lần; thời gian Terraform của Case 1 có gồm.

### 2.2 Chịu lỗi (RTO/RPO) đã đo

| Kịch bản | Sự cố mô phỏng | RTO đo được | Dữ liệu |
|---|---|---|---|
| Case 1 | Xóa instance | 449.48 s (thay thế thủ công) | Mất 100% dữ liệu trong RAM |
| Case 2 | DB chiếm CPU/RAM máy chung | 34.96 s | Không mất |
| Case 2 | Xóa container + volume, restore từ S3 | 82.49 s | Dữ liệu sau backup cuối bị mất (Order #103); xem ghi chú test 2C trong `docs/Day2` |
| Case 3 | Tắt Web tier | 86.05 s | Không mất (Order #201) |
| Case 3 | Dừng PostgreSQL, restore từ S3 | 44.07 s | Tới 1 giờ (dump hằng giờ) |
| Case 4 | Reboot RDS (Single-AZ) | 11.46 s | Không mất (Order #401) |
| Case 4 | PITR | Instance mới sẵn sàng sau ~8–10 phút | Điểm khôi phục chọn trước đó 1 giây |

### 2.3 Số liệu chưa đo (không dùng để so sánh)

- Case 2: thay thế hoàn toàn EC2 — 5–8 phút **(ước lượng)**.
- Case 3: thay thế DB EC2 từ EBS snapshot — 15–20 phút **(ước lượng)**.
- Case 4: failover Multi-AZ — thường 60–120 giây theo tài liệu AWS; **chưa đo** vì chưa triển khai Multi-AZ. Mục tiêu RPO của PITR (thường trong vòng 5 phút) theo thiết kế AWS **(ước lượng)**.
- Cô lập tài nguyên Web/DB khi quá tải ở Case 3–4; thời gian gửi cảnh báo CloudWatch/SNS; Terraform toàn trình của Case 2–4.
