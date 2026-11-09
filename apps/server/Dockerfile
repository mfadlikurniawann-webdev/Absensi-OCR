FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEEPFACE_HOME=/models \
    DB_PATH=/data/absensi.db \
    APP_TIMEZONE=Asia/Jakarta \
    TZ=Asia/Jakarta \
    PORT=5000

RUN apt-get update \
    && apt-get install -y --no-install-recommends libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

# Unduh bobot model Facenet & detektor wajah saat build, supaya request
# pertama di server tidak lambat / gagal karena download.
RUN python -c "from deepface import DeepFace; DeepFace.build_model('Facenet'); DeepFace.build_model('opencv', task='face_detector')"

COPY app.py .
COPY templates ./templates
COPY static ./static

RUN useradd --create-home --uid 1000 appuser \
    && mkdir -p /data \
    && chown -R appuser:appuser /data /models
USER appuser

VOLUME ["/data"]
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/api/health" || exit 1

# 1 worker karena model wajah dimuat di memori; thread menangani request paralel.
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 1 --threads 4 --timeout 120 app:app"]
