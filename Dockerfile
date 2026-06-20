FROM python:3.12-slim

WORKDIR /app

# Install dependencies first for layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY src/ ./src/
COPY main.py .

# Cloud Run expects the service to listen on $PORT (default 8080)
ENV PORT=8080

EXPOSE 8080

# Use gunicorn with a single worker for Cloud Run (scales via instances, not workers)
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", "--timeout", "60", "main:app"]
