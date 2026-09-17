# QROS Gateway — Dockerfile (Stage 2: wired)
FROM python:3.11-slim

LABEL service="qros-gateway" version="1.0.0-stage2" purpose="OpenAI routing for QROS Control Center — Telegram → GitHub → AgentOS"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY README.md ./

RUN useradd -m -u 1000 appuser && mkdir -p /app/logs && chown -R appuser:appuser /app && chmod 755 /app/logs
USER appuser

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=15s CMD python -c "import urllib.request,os; urllib.request.urlopen(f'http://localhost:{os.getenv(\"PORT\",\"8080\")}/health', timeout=2).read()" || exit 1

CMD ["python", "-m", "src.main"]
