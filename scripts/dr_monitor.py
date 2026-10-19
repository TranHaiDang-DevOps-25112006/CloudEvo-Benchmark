import urllib.request
import urllib.error
import json
import time
import sys
from datetime import datetime

def monitor(target_url):
    if not target_url.startswith("http"):
        target_url = f"http://{target_url}"
    if not target_url.endswith("/health"):
        target_url = target_url.rstrip("/") + "/health"

    print("=" * 72)
    print(f"[CloudEvo DR Monitor] Bắt đầu theo dõi: {target_url}")
    print("Nhấn Ctrl + C để dừng theo dõi.")
    print("=" * 72)

    is_down = False
    down_start_time = None
    failure_count = 0

    try:
        while True:
            now_str = datetime.now().strftime("%H:%M:%S")
            req_start = time.time()
            try:
                req = urllib.request.Request(target_url, headers={"User-Agent": "CloudEvo-DR-Monitor/1.0"})
                with urllib.request.urlopen(req, timeout=2.0) as response:
                    latency_ms = int((time.time() - req_start) * 1000)
                    body = response.read().decode("utf-8")
                    data = json.loads(body)
                    status = data.get("status", "UNKNOWN")

                    if status == "UP":
                        if is_down:
                            rto_seconds = round(time.time() - down_start_time, 2)
                            print("\n" + "#" * 72)
                            print(f"[RECOVERED - KHÔI PHỤC THÀNH CÔNG] Lúc {now_str}")
                            print(f"=> TỔNG THỜI GIAN GIÁN ĐOẠN (RTO THỰC TẾ): {rto_seconds} giây ({failure_count} lần ping lỗi)")
                            print(f"=> Hostname mới: {data.get('hostname')} | Mode: {data.get('mode')}")
                            print("#" * 72 + "\n")
                            is_down = False
                            down_start_time = None
                            failure_count = 0

                        print(f"[{now_str}] [UP] HTTP 200 | Mode: {data.get('mode')} | DB: {data.get('db_connected')} | Latency: {latency_ms}ms | Host: {data.get('hostname')}")
                    else:
                        raise Exception(f"Health status returned {status}")

            except Exception as e:
                failure_count += 1
                if not is_down:
                    is_down = True
                    down_start_time = time.time()
                    print("\n" + "!" * 72)
                    print(f"[INCIDENT DETECTED - PHÁT HIỆN SỰ CỐ] Lúc {now_str} — Bắt đầu bấm giờ RTO!")
                    print("!" * 72)

                elapsed_down = int(time.time() - down_start_time)
                print(f"[{now_str}] [DOWN #{failure_count}] Downtime: {elapsed_down}s | Lý do: {e}")

            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[CloudEvo DR Monitor] Đã dừng theo dõi.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Cách dùng: python scripts/dr_monitor.py <EC2_PUBLIC_IP_HOẶC_URL>")
        print("Ví dụ:     python scripts/dr_monitor.py 13.212.45.67")
        sys.exit(1)
    monitor(sys.argv[1])