# QROS Bot — Dockerfile (Stage 2: wired, no business logic)
FROM python:3.11-slim

LABEL service="qros-bot" version="1.0.0-stage2" purpose="remote project management — Telegram front for QROS Control Center"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# System deps (curl for healthcheck, ca-certificates)
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY README.md ./

# Non-root
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=20s CMD python -c "import urllib.request,os; urllib.request.urlopen(f'http://localhost:{os.getenv(\"PORT\",\"8081\")}/health', timeout=2).read()" || exit 1

# Stage 1: placeholder entrypoint — validates config, exposes /health, does not poll Telegram yet
CMD ["python", "-m", "src.main"]
