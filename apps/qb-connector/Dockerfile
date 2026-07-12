FROM python:3.12-slim

WORKDIR /app

# Install 1Password CLI (arm64 for Apple Silicon Mac)
RUN apt-get update && apt-get install -y curl gpg && \
    curl -sS https://downloads.1password.com/linux/debian/arm64/stable/1password-cli-arm64-latest.deb -o /tmp/op.deb && \
    dpkg -i /tmp/op.deb || apt-get install -f -y && \
    rm /tmp/op.deb && \
    apt-get clean

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8085

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8085/health')" || exit 1

CMD ["python3", "app.py"]
