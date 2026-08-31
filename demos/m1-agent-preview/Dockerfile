FROM python:3.13-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim

RUN useradd --create-home --shell /usr/sbin/nologin appuser
COPY --from=builder /install /usr/local
WORKDIR /app
COPY app/app.py .
USER appuser

EXPOSE 5000
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["python", "app.py"]
