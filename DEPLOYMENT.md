# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị token vào đây.**
> Repo này công khai — dán token vào là mất token.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Nguyễn Tiến Đạt |
| Mã học viên | 2A202601963 |
| Repo | https://github.com/nguyendat2662003/K4-DAY12-2A202601963-NguyenTienDat |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://day12-chat-kyxq.onrender.com |
| Platform | Render (Blueprint đọc từ `render.yaml`, runtime Docker) |
| Ngày deploy | 10/08/2026 |

Render build trực tiếp từ `Dockerfile` trong repo, không cần build ở máy local.
Hai service được tạo cùng lúc từ `render.yaml`: `day12-chat` (web) và
`day12-chat-redis` (key-value store).

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Render tự gán; `Dockerfile` đọc `${PORT}` nên không cố định 8000 |
| `API_TOKEN` | ✅ | khai báo `sync: false` trong `render.yaml` → Render hỏi lúc deploy, không lưu vào repo |
| `REDIS_URL` | ✅ | key-value store `day12-chat-redis` của Render, nối tự động qua `fromService` |
| `BUCKET_CAPACITY` | ✅ | 10 |
| `REFILL_PER_MINUTE` | ✅ | 10 |
| `DAILY_BUDGET_USD` | ✅ | 1.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

```bash
URL=https://day12-chat-kyxq.onrender.com

# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i $URL/healthz

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i $URL/readyz

# 3. Không có token — mong đợi 401 kèm header WWW-Authenticate
curl -i -X POST $URL/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello"}'

# 4. Có token — mong đợi 200 kèm câu trả lời
curl -i -X POST $URL/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Client-Id: sv-demo" \
  -d '{"message":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST $URL/chat \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Client-Id: rl-demo" \
    -d '{"message":"test"}'
done; echo
```

Máy mình chạy Windows nên thực tế gọi bằng PowerShell. Lưu ý `curl` trong
PowerShell là alias của `Invoke-WebRequest` chứ không phải curl thật — phải
gõ `curl.exe`, nếu không `-i` bị hiểu thành `-InFile` và lệnh không hề được
gửi đi:

```powershell
$URL = "https://day12-chat-kyxq.onrender.com"
curl.exe -i $URL/healthz

# vòng lặp 15 lần, tương đương `for` của bash
1..15 | ForEach-Object {
  curl.exe -s -o NUL -w "%{http_code} " -X POST $URL/chat `
    -H "Content-Type: application/json" `
    -H "Authorization: Bearer $TOKEN" `
    -H "X-Client-Id: rl-demo" -d '{\"message\":\"test\"}'
}
```

## Kết Quả Chạy Thật

Đã lược bớt các header hạ tầng của Cloudflare/Render cho gọn.

```
=== 1. GET /healthz ===
HTTP/1.1 200 OK
Content-Type: application/json
x-render-origin-server: uvicorn

{"status":"ok","service":"day12-chat-service","version":"1.0.0"}

=== 2. GET /readyz ===
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"ready","redis":true}

=== 3. POST /chat — không token ===
HTTP/1.1 401 Unauthorized
Content-Type: application/json
www-authenticate: Bearer

{"detail":"invalid or missing bearer token"}

=== 4. POST /chat — có token ===
HTTP/1.1 200 OK
Content-Type: application/json

{"reply":"Ngắn gọn: Deploy la gi phụ thuộc vào ba yếu tố — cấu hình qua biến
môi trường, health check để orchestrator biết trạng thái, và giới hạn tài
nguyên.","client_id":"sv-demo","turns_before":0,"usd_cost":2.265e-05,
"usage":{"prompt":3,"completion":37}}

=== 5. Rate limit — 15 request liên tiếp ===
200 200 200 200 200 200 200 200 200 200 429 200 429 429 429
```

Đọc kết quả:

- `/readyz` trả `redis: true` → service trên cloud thật sự nối được key-value
  store, không phải chỉ "process còn sống".
- Đúng **10** request đầu được phục vụ rồi mới có 429 — khớp
  `BUCKET_CAPACITY=10`.
- Cái `200` xen giữa các `429` ở lượt thứ 12 không phải lỗi: với
  `REFILL_PER_MINUTE=10`, xô được nạp lại 1 token mỗi 6 giây. Loạt request này
  đi qua Internet nên đủ chậm để một token kịp nhỏ vào xô. Đây chính là điểm
  khác biệt của token bucket so với bộ đếm cứng "N request mỗi phút".
- `usd_cost` được trả về theo từng lượt và cộng dồn vào ngân sách ngày của
  từng `X-Client-Id`.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/healthz.png` — kết quả gọi `/healthz` từ trình duyệt hoặc curl

## Ghi Chú

Service không khai báo route `/`, nên mở URL trần trong trình duyệt sẽ trả
404 — đúng thiết kế, vì hợp đồng API chỉ gồm `/healthz`, `/readyz` và `/chat`.
Muốn xem giao diện thì mở `/docs` (Swagger UI do FastAPI tự sinh).

Gói free của Render cho service ngủ sau khoảng 15 phút không có traffic, nên
request đầu tiên sau khi ngủ có thể mất 30–50 giây. `tests/test_cp5.py` đã
tính tới điều này bằng `FIRST_CALL_TIMEOUT = 60.0`.
