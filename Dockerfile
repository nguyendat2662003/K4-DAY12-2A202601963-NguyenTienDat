# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (bản production-ready)
#
# Multi-stage: stage `builder` có toolchain để biên dịch wheel, stage runtime
# chỉ nhận thư mục thư viện đã cài xong → image nhỏ, không mang theo compiler.
#
# Build thử: docker build -t day12-chat:prod .
#            docker images day12-chat:prod
# ═══════════════════════════════════════════════════════════════════

# ─────────────── Stage 1: builder ───────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Cài thư viện vào một prefix riêng để copy nguyên khối sang stage sau.
# COPY requirements.txt TRƯỚC khi copy source: sửa một dòng code không làm
# hỏng cache của layer pip install.
COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ─────────────── Stage 2: runtime ───────────────
FROM python:3.11-slim AS runtime

# PYTHONDONTWRITEBYTECODE: không sinh .pyc rác trong container
# PYTHONUNBUFFERED: log ra stdout ngay, không nằm kẹt trong buffer
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# Chỉ lấy kết quả cài đặt từ builder — gcc, header, cache pip ở lại stage kia
COPY --from=builder /install /usr/local

# Tạo user thường: thoát được khỏi app cũng chỉ là `appuser`, không phải root
RUN useradd --create-home --uid 1000 appuser

COPY --chown=appuser:appuser app/ ./app/
COPY --chown=appuser:appuser utils/ ./utils/

USER appuser

EXPOSE 8000

# Không có curl trong image slim — dùng luôn Python để gọi /healthz
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os,urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/healthz', timeout=4).status == 200 else 1)"

# Dạng shell để ${PORT} được giãn ra — cloud tự gán cổng, không cố định 8000
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT}
