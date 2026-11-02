#!/usr/bin/env python3
import argparse
import random
import statistics
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


def normalize(target: str) -> str:
    target = target.strip().rstrip("/")
    if not target.startswith(("http://", "https://")):
        target = "http://" + target
    return target


def worker(base, stop_at, post_ratio, timeout, results, lock):
    while time.time() < stop_at:
        is_post = random.random() < post_ratio
        started = time.perf_counter()
        status = 0
        try:
            if is_post:
                data = urllib.parse.urlencode({"customer": "load-test", "amount": f"{random.randint(1, 500)}.00"}).encode()
                req = urllib.request.Request(base + "/api/transactions", data=data, method="POST")
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    status = resp.status
            else:
                with urllib.request.urlopen(base + "/health", timeout=timeout) as resp:
                    status = resp.status
        except urllib.error.HTTPError as err:
            status = err.code
        except Exception:
            status = 0
        elapsed_ms = (time.perf_counter() - started) * 1000
        with lock:
            results.append((time.time(), status, elapsed_ms))


def percentile(values, pct):
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(pct / 100 * (len(ordered) - 1))))]


def main():
    parser = argparse.ArgumentParser(description="CloudEvo load generator")
    parser.add_argument("target", help="IP hoặc URL của web tier (ví dụ 13.212.204.91)")
    parser.add_argument("--duration", type=int, default=60, help="Thời gian chạy (giây), mặc định 60")
    parser.add_argument("--concurrency", type=int, default=5, help="Số luồng song song, mặc định 5")
    parser.add_argument("--post-ratio", type=float, default=0.0, help="Tỉ lệ request POST /api/transactions (0-1), mặc định 0")
    parser.add_argument("--timeout", type=float, default=3.0, help="Timeout mỗi request (giây), mặc định 3")
    args = parser.parse_args()

    base = normalize(args.target)
    results, lock = [], threading.Lock()
    stop_at = time.time() + args.duration
    print(f"[LOAD] {base} | {args.concurrency} luồng | {args.duration}s | POST ratio {args.post_ratio}")
    threads = [threading.Thread(target=worker, args=(base, stop_at, args.post_ratio, args.timeout, results, lock), daemon=True)
               for _ in range(args.concurrency)]
    for t in threads:
        t.start()

    last_print = time.time()
    while time.time() < stop_at:
        time.sleep(1)
        if time.time() - last_print >= 5:
            with lock:
                recent = [r for r in results if r[0] >= time.time() - 5]
            ok = sum(1 for r in recent if 200 <= r[1] < 400)
            print(f"[{time.strftime('%H:%M:%S')}] ~{len(recent) / 5:.1f} req/s | thành công {ok}/{len(recent)}")
            last_print = time.time()
    for t in threads:
        t.join(timeout=args.timeout + 1)

    total = len(results)
    ok = [r for r in results if 200 <= r[1] < 400]
    errors = total - len(ok)
    lat = [r[2] for r in ok]
    print("\n===== KẾT QUẢ =====")
    print(f"Tổng request : {total} | thành công: {len(ok)} | lỗi: {errors} ({(errors / total * 100) if total else 0:.1f}%)")
    if lat:
        print(f"Độ trễ (ms)  : trung bình {statistics.mean(lat):.1f} | p50 {percentile(lat, 50):.1f} | p95 {percentile(lat, 95):.1f} | max {max(lat):.1f}")
    codes = {}
    for r in results:
        codes[r[1]] = codes.get(r[1], 0) + 1
    print("Mã trạng thái:", dict(sorted(codes.items())))


if __name__ == "__main__":
    main()
