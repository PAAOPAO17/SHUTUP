FROM python:3.12-slim
RUN pip install --no-cache-dir "webauthn>=2.1,<3" pywebpush qrcode
WORKDIR /app
COPY server.py index.html setup.html sw.js manifest.webmanifest icon-192.png icon-512.png apple-touch-icon.png ./
CMD ["python", "-u", "server.py"]
