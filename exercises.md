# Phiếu Phản Ánh — K4 Ngày 12

> Họ và tên: Nguyễn Tiến Đạt  Mã học viên: 2A202601963

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `api_token` không có giá trị mặc định nên app chết ngay khi
khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà việc
"chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Lúc tạo Blueprint trên Render, `render.yaml` khai `API_TOKEN` với `sync: false`
nên Render dừng lại hỏi mình giá trị. Giả sử mình sốt ruột bấm qua.

Nếu có mặc định `"changeme"`: container vẫn lên, `/healthz` trả 200, Render báo
**Live** màu xanh — không một dấu hiệu nào cho biết có gì sai. Nhưng URL là địa
chỉ công khai, và `"changeme"` là chuỗi đầu tiên ai cũng thử. Mình chỉ phát hiện
khi nhìn hóa đơn, hoặc khi ngân sách bị đốt hết và service trả 402 cho chính
mình.

Thực tế thì `Settings()` ném `ValidationError` ngay lúc khởi động, container
chết, Render báo deploy failed và **giữ nguyên bản cũ đang chạy**. Mình thấy lỗi
trong log sau chưa tới một phút, thiệt hại bằng 0.

Mặc định cho secret không phải là "tiện" — nó đổi một lỗi ồn ào lúc khởi động
lấy một lỗ hổng im lặng khi đang chạy.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/chat` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

```json
{"event": "chat_completed", "severity": "INFO", "ts": "2026-08-10T10:31:44.812416+00:00", "client_id": "sv-demo", "prompt_tokens": 3, "completion_tokens": 37, "usd_cost": 2.265e-05}
```

**1. Cộng tiền theo từng client.** `client_id` và `usd_cost` là hai trường riêng
biệt nên mình nhóm theo `client_id` rồi cộng `usd_cost` là biết ai đốt nhiều
tiền nhất, đối chiếu thẳng được với `DAILY_BUDGET_USD`. Với `print` thì không có
gì để nhóm, không có gì để cộng.

**2. Đặt cảnh báo tự động.** `severity` viết hoa là khóa mà Google Cloud Logging
và Datadog hiểu sẵn, nên mình đặt được luật kiểu "quá 10 dòng ERROR trong 5 phút
thì báo Slack" mà không phải viết regex. `ts` chuẩn ISO-8601 kèm UTC cho phép
sắp xếp theo thời gian kể cả khi log của 3 container trộn lẫn.

Khác biệt cốt lõi: JSON là **dữ liệu** để máy truy vấn, `print` là **câu văn**
để người đọc — mà production không ai ngồi đọc log của 3 container cùng lúc.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1.73 GB |
| Multi-stage | 270 MB |

Nhỏ hơn **6,4 lần**, tiết kiệm ~1,5 GB mỗi lần kéo image.

Giải thích: phần dung lượng chênh lệch đó là những gì?

**Base image.** Bản đầu dùng `python:3.11` đầy đủ, mang theo cả `gcc`, `make`,
header C, `git` — toàn bộ đều chỉ cần lúc *cài* thư viện, không cần lúc phục vụ
request. Bản của mình dùng `python:3.11-slim`.

**Rác của quá trình build.** Stage `builder` chạy `pip install --prefix=/install`
sinh ra source tải về, wheel đã biên dịch và cache pip. Stage runtime chỉ
`COPY --from=builder /install /usr/local` nên chỉ bê sang kết quả cuối. Bản một
stage thì mọi thứ nằm lại trong layer — xóa file ở layer sau cũng không làm image
nhỏ đi vì layer trước vẫn còn trong lịch sử.

**File của máy dev.** `COPY . .` của bản đầu nuốt cả `.venv`, `.git`,
`__pycache__` vào image. `.dockerignore` chặn hết những thứ đó.

Không thứ nào trong ba nguồn trên cần thiết để trả lời một request HTTP, nhưng
đều phải tải về mỗi lần kéo image và đều là thêm phần mềm có thể chứa lỗ hổng.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Docker băm nội dung từng bước làm khóa cache và duyệt tuần tự; **bước đầu tiên
lệch khóa kéo theo mọi bước sau phải chạy lại**.

Sửa `app/main.py` với Dockerfile của mình:

- **Dùng lại cache** — cả stage `builder` (`COPY requirements.txt`, `RUN pip
  install`) vì `requirements.txt` không đổi. Đây là bước tốn vài phút. Ở runtime
  thì `FROM`, `ENV`, `COPY --from=builder`, `RUN useradd` cũng được dùng lại.
- **Chạy lại** — từ `COPY app/ ./app/` trở đi (`COPY utils/`, `USER`,
  `HEALTHCHECK`, `CMD`). Toàn thao tác copy vài chục KB nên chỉ mất vài giây.

Đó là lý do mình tách `COPY requirements.txt` khỏi việc copy source: danh sách
thư viện vài tuần mới sửa, còn code sửa vài chục lần một ngày.

Nếu `COPY . .` đứng trước `RUN pip install`, khóa cache của bước COPY phụ thuộc
**mọi file trong repo** → sửa một ký tự là vỡ, và `pip install` nằm sau nên vỡ
theo. Mỗi lần sửa một dòng code là cài lại toàn bộ thư viện, build từ vài giây
thành vài phút — nhân với số lần build mỗi ngày và mỗi lần CI chạy.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

1. **Chạy được lệnh tùy ý trong container** — từ một lỗ hổng trong code Python
   (dữ liệu người dùng lọt vào `os.system()`, thư viện có lỗi deserialize). Họ
   thực thi lệnh **với đúng quyền của process uvicorn**.
2. **Quyền đó là root** — không có `USER` thì process chạy uid 0: cài thêm công
   cụ, đọc mọi biến môi trường kể cả `API_TOKEN`, dùng được capability kernel.
3. **Từ root trong container tìm đường ra host** — container dùng chung kernel
   với host, chỉ ngăn bằng namespace. Root là bàn đạp để khai thác lỗ hổng
   escape, hoặc lợi dụng volume mount nhầm / `docker.sock` bị gắn vào.
4. **Root container thành root host** — user namespace mặc định không bật nên
   uid 0 bên trong ánh xạ thẳng thành uid 0 bên ngoài.

`USER appuser` cắt chuỗi ở **mắt xích 2**: process chạy uid 1000, nên tới bước 1
kẻ tấn công chỉ giành được quyền một user thường — không cài được gói, không ghi
được `/usr/local`, không dùng được capability. Bước 3 mất gần hết bàn đạp, và có
escape ra được thì bước 4 cũng chỉ cho uid 1000 trên host.

Least privilege: mình không ngăn được mọi lỗ hổng, nhưng quyết định được **lỗ
hổng đó đáng giá bao nhiêu** — đổi lại chỉ hai dòng `RUN useradd` và `USER`.

---

### Câu 6 — Bearer token (CP3)

Vì sao 401 phải kèm header `WWW-Authenticate: Bearer`? Và vì sao ta trả **cùng
một** thông báo lỗi cho cả ba trường hợp (thiếu header, sai scheme, sai token)
thay vì nói rõ sai ở đâu cho người dùng dễ sửa?

**`WWW-Authenticate`** là bắt buộc theo RFC 7235, giá trị `Bearer` theo RFC 6750.
Vì 401 tự nó chỉ nói "bạn chưa được xác thực" chứ không nói **xác thực bằng cách
nào** — Basic, Digest hay Bearer. Header này là câu trả lời đó, nhờ nó client
viết bằng ngôn ngữ nào cũng biết phải gắn `Authorization: Bearer <token>`. Kết
quả thật trên bản deploy:

```
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer

{"detail":"invalid or missing bearer token"}
```

**Dùng chung một thông báo** vì thông báo chi tiết là quà cho người đang dò
token, không phải cho người dùng hợp lệ — người hợp lệ đọc tài liệu một lần là
gắn đúng ngay. Tách bạch "thiếu header" / "sai scheme" / "sai token" là tạo ra
một **oracle**: chỉ riêng việc phân biệt được "token sai" với "định dạng sai" đã
xác nhận cho kẻ tấn công rằng request của họ đã đúng cấu trúc và giờ chỉ còn dò
giá trị. Cùng một câu trả lời cho cả ba nhánh thì mọi lần thử sai đều cho đúng
một kết quả.

Cùng logic đó, `auth.py` so token bằng `secrets.compare_digest` chứ không `==`.
`==` dừng ở ký tự đầu khác nhau nên thời gian phản hồi rò rỉ đã đoán đúng bao
nhiêu ký tự. Bịt thông báo lỗi mà để hở thời gian phản hồi thì bằng thừa.

---

### Câu 7 — Token bucket (CP3)

Với `capacity=10`, `refill_per_minute=10`: một client im lặng 10 phút rồi gửi
liên tiếp. Nó gửi được bao nhiêu request trước khi bị 429? Nếu bỏ đoạn
`min(capacity, ...)` trong `available()` thì con số đó thành bao nhiêu, và tại sao?

**Có `min`: đúng 10 request.** Sau 10 phút im lặng phép tính cho ra
`600 × (10/60) = 100` token, nhưng `min(float(self.capacity), tokens)` kẹp lại ở
10. Im lặng bao lâu cũng không tích quá 10. Mình kiểm chứng bằng 15 request liên
tiếp lên bản deploy:

```
200 200 200 200 200 200 200 200 200 200 429 200 429 429 429
```

Đúng 10 lần `200` rồi mới `429`. Cái `200` xen vào ở lượt 12 không phải lỗi: cứ
6 giây có một token nhỏ vào xô, mà loạt request đi qua Internet đủ chậm để một
token kịp hồi — đây chính là chỗ token bucket khác bộ đếm cứng "N request mỗi
phút".

**Bỏ `min`: thành 100.** Không còn trần thì `tokens += (now - last) ×
refill_per_second` cộng dồn tuyến tính: 10 phút cho 100, một giờ cho 600, một
ngày cho 14.400.

`capacity` không chỉ là "sức chứa" mà là **mức bùng tối đa hệ thống chịu được
trong một khoảnh khắc**. Một client bắn 14.400 request trong vài giây sẽ làm sập
service dù tốc độ trung bình vẫn trong giới hạn. Dòng `min` là thứ tách "tốc độ
trung bình cho phép" (`refill_per_minute`) khỏi "mức bùng cho phép"
(`capacity`) — thiếu nó thì khái niệm thứ hai biến mất.

---

### Câu 8 — Ngân sách theo ngày (CP3)

So sánh hạn mức $30/tháng với hạn mức $1/ngày cho cùng một client. Giả sử có sự
cố khiến một client gọi liên tục từ 2h sáng. Với mỗi cách, thiệt hại tối đa là
bao nhiêu và service tự hồi phục khi nào?

| | $30/tháng | $1/ngày |
|---|---|---|
| Thiệt hại tối đa | **$30** — sạch ngân sách cả tháng trong một đêm | **$1** |
| Hồi phục | ngày đầu tháng sau, hoặc phải nâng hạn mức **bằng tay** | tự động khi sang ngày mới |

Với hạn mức tháng, sự cố bắt đầu 2h sáng thì tới lúc mình dậy tiền đã đi hết. Tệ
hơn là chuyện sau đó: ngân sách cạn nên service trả 402 cho *tất cả* request tới
đầu tháng sau — nếu hôm đó là mùng 3 thì mất 27 ngày dịch vụ.

Với hạn mức ngày, client đốt hết $1 rồi bị `CostGuard.check()` chặn, sự cố dừng
tại đó. Service tự hồi phục vì `_key()` gắn ngày vào tên khóa Redis
(`spend:<client_id>:2026-08-10`) — ngày mới là khóa mới, chưa tồn tại, `spent()`
trả 0.0.

Lưu ý múi giờ: `today()` dùng `datetime.now(timezone.utc)` nên 2h sáng giờ Việt
Nam là 19h00 UTC hôm trước, còn 5 tiếng nữa mới sang ngày UTC mới — service hồi
phục lúc **7h sáng giờ Việt Nam**. Dùng UTC là cố ý: không đổi theo daylight
saving và giống nhau ở mọi instance dù chạy region nào.

Hạn mức tháng **báo động sau khi tiền đã mất**; hạn mức ngày **giới hạn thiệt
hại** và tự đặt lại. Cùng số tiền, một bên là báo cáo, một bên là hàng rào.

---

### Câu 9 — /healthz khác /readyz (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

1. Redis mất kết nối. Ba container vẫn sống, code không lỗi.
2. Liveness probe gọi endpoint gộp → `ping()` thất bại → cả ba cùng trả 503.
   **Cùng lúc**, vì chúng dùng chung một Redis: không phải ba sự cố độc lập mà
   là một sự cố nhân lên ba.
3. Orchestrator hiểu 503 ở liveness đúng nghĩa của nó — "process hỏng, restart"
   — nên giết cả ba. Đây là chỗ sai lệch nặng nhất: process hoàn toàn khỏe, thứ
   hỏng là dependency, nhưng orchestrator không biết vì mình đã trộn hai câu hỏi
   khác nhau vào một endpoint.
4. Cả ba khởi động lại → không container nào phục vụ, kể cả request không đụng
   Redis. Downtime 100%, không phải suy giảm một phần.
5. Container mới lên, Redis vẫn chưa hồi → lại 503 → lại restart. Đây là **crash
   loop**, orchestrator tăng dần thời gian chờ (backoff).
6. Redis hồi ở giây 30, nhưng cả ba đang trong backoff hoặc khởi động dở. Sự cố
   30 giây của Redis kéo theo downtime dài hơn hẳn 30 giây.

Với thiết kế tách đôi: `/healthz` không nhận dependency nào (test
`test_healthz_khong_phu_thuoc_dependency_nao` soi chữ ký hàm để đảm bảo điều
này) nên vẫn 200, không container nào bị restart. `/readyz` gọi `store.ping()`
nên trả 503, load balancer hiểu đúng là "còn sống nhưng chưa phục vụ được, đừng
đẩy traffic vào". Giây 30 Redis lên lại, `/readyz` trả 200 ở lần probe kế tiếp,
traffic quay lại tức thì — đúng 30 giây, không mất container nào.

Hai endpoint trả lời hai câu hỏi khác nhau: `/healthz` hỏi "có cần restart
không?", `/readyz` hỏi "có nên gửi traffic vào không?". Gộp lại là ép
orchestrator dùng búa tạ cho việc chỉ cần tạm ngắt đường traffic.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Thông báo lỗi.** Deploy xong, `/healthz` và `/readyz` đều 200, `/chat` không
token trả 401 đúng mong đợi. Nhưng gọi `/chat` **kèm token đúng** vẫn nhận:

```
HTTP/1.1 401 Unauthorized
{"detail":"invalid or missing bearer token"}
```

Khó chịu ở chỗ nhìn bằng mắt thì token trong `.env` và token trên Render giống
hệt nhau.

**Tìm nguyên nhân.** Loại trừ dần: service sống, Redis nối được (`/readyz` trả
`redis: true`), logic auth đúng vì 29 test CP3 đều xanh. Vậy vấn đề ở **giá trị**
token chứ không phải code. Thay vì nhìn, mình **đo**:
`secrets.token_urlsafe(32)` luôn sinh chuỗi đúng **43 ký tự** không khoảng
trắng, mà chuỗi đọc từ `.env` dài **44** và có một khoảng trắng. Thủ phạm là dấu
cách lọt vào ngay sau dấu `=` khi dán token — trình soạn thảo không hiển thị nó.
`compare_digest` so từng byte nên 44 byte không bao giờ khớp 43 byte.

**Cách sửa.** Xóa dấu cách trong `.env`, xác nhận lại độ dài 43, `/chat` trả 200.

**Bài học.** Với dữ liệu mắt người không kiểm tra được — token, hash, khóa — phải
kiểm bằng thuộc tính đo được như độ dài, thay vì kết luận "trông giống nhau mà".
Mình cũng hiểu thêm cái giá của thông báo lỗi mơ hồ ở Câu 6: nó giấu thông tin
với kẻ tấn công, nhưng lúc debug thì mình cũng không được biết sai ở đâu.
