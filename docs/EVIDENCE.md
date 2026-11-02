# 🔎 Bảng đối chiếu: số liệu → bằng chứng → cách đo

Mọi số liệu trong báo cáo tổng thể truy vết được tới báo cáo từng ngày (`docs/DayN`, kèm ảnh chụp) và log của `scripts/dr_monitor.py`. Mỗi phép đo là **một lần chạy**.

| # | Số liệu / nội dung | Giá trị | Bằng chứng | Cách đo |
|---|---|---|---|---|
| 1 | Case 1: dựng bằng ClickOps | 20 phút | `docs/Day1` | Tự bấm giờ (một lần) |
| 2 | Case 1: User Data | 2 phút 48s | `docs/Day1` (Hình 5; `/var/log/user-data.log`) | Từ lúc khởi chạy tới `/health` hợp lệ |
| 3 | Case 1: RTO khi xóa instance | 449.48 s (150 ping lỗi) | `docs/Day1` (Hình 6–7) | `dr_monitor.py`; gồm thao tác thủ công |
| 4 | Case 1: Terraform apply / destroy | ~1m 45s / ~45 s, 21 tài nguyên | `docs/Day5` (Hình 2, Hình 5) | `terraform apply/destroy -var scenario_case=1` |
| 5 | CI GitHub Actions | ~55 s | `docs/Day5` (Hình 4) | Thời gian một lần chạy (2 job song song) |
| 6 | Case 2: IAM policy S3 | Giới hạn trong một bucket | `docs/Day2` (Hình 1) | Chụp policy |
| 7 | Case 2: backup lên S3 | ~4 s | `docs/Day2` (Hình 2) | Chạy `backup_s3.sh` rồi `aws s3 ls` |
| 8 | Case 2: DB chiếm CPU/RAM | 34.96 s (12 ping lỗi) | `docs/Day2` (Hình 5) | `dr_monitor.py` + stress-ng |
| 9 | Case 2: xóa container + volume, restore S3 | 82.49 s (28 ping lỗi) | `docs/Day2` (Hình 6) | `dr_monitor.py` |
| 10 | Case 2: RPO | Order #103 mất; Order #1 có timestamp mới (13:22:34 UTC) | `docs/Day2` (Hình 7–8) | Lần chạy riêng; **chưa chứng minh dump được nạp** (xem README, Known issues) |
| 11 | Case 3: security-group chaining | DB chỉ nhận 5432/22 từ SG của Web | `docs/Day3` (Hình 1) | Chụp rule SG |
| 12 | Case 3: query Web → DB | 12 ms; Order #201 | `docs/Day3` (Hình 4–5) | `/health` |
| 13 | Case 3: Web tier bị tắt | 86.05 s (29 ping lỗi) | `docs/Day3` (Hình 6) | `dr_monitor.py` |
| 14 | Case 3: DB dừng + restore S3 | 44.07 s (39 ping lỗi, Web trả HTTP 503) | `docs/Day3` (Hình 7) | `dr_monitor.py` |
| 15 | Case 4: tạo RDS | ~8 phút 30s | `docs/Day4` (Hình 2) | Console / log |
| 16 | Case 4: cấu hình RDS | PostgreSQL 16.10, `db.t4g.micro`, 20 GiB gp3, KMS, Single-AZ | `docs/Day4` (Hình 1, 3) | Chụp console |
| 17 | Case 4: kết nối Web → RDS | 2–28 ms; Order #401 | `docs/Day4` (Hình 4–5) | `/health` |
| 18 | Case 4: RTO reboot RDS | 11.46 s (10 ping lỗi) | `docs/Day4` (Hình 6) | `dr_monitor.py` |
| 19 | Case 4: PITR | Instance mới sẵn sàng sau ~8–10 phút | `docs/Day4` (Hình 7–8) | Console |
| 20 | Chi phí hàng tháng | $15.21 / $16.55 / $28.10 / $36.22 ($57.96 Multi-AZ) | `docs/FINOPS_AND_BENCHMARK_MATRIX.md` | Tính từ bảng giá công bố, **không phải hóa đơn** |
| 21 | NAT Gateway tránh được | $43.07/tháng | `docs/FINOPS_AND_BENCHMARK_MATRIX.md` | Tính từ bảng giá ($0.059/giờ × 730) |
| 22 | Lớp giám sát CloudWatch/SNS | Đã thiết kế; **chưa đo** thời gian gửi cảnh báo | `terraform/monitoring.tf`, `docs/Day6` | — |

**Chưa đo / ước lượng:** Terraform của Case 2–4; failover Multi-AZ; thay thế hoàn toàn EC2 (5–8 phút) và DB EC2 (15–20 phút); cô lập tài nguyên dưới tải ở Case 3–4; thời gian gửi cảnh báo.
