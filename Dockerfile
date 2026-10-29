# ---- build stage: install deps into an isolated prefix ----
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- runtime stage: slim, non-root ----
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --system --uid 10001 --no-create-home appuser
WORKDIR /srv
COPY --from=builder /install /usr/local
COPY app/ ./app/
USER 10001
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health').status==200 else 1)"
# 1 worker + threads: keeps prometheus_client counters consistent (no multiprocess mode needed)
CMD ["gunicorn", "-w", "1", "--threads", "4", "-b", "0.0.0.0:5000", "app.app:app"]
