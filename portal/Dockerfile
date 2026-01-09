FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && \
    apt-get install -y openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ /app/

# Create necessary directories
RUN mkdir -p /app/certs /app/data

# Create non-root user with GID 1000 to match PKI directory group
RUN groupadd -g 1000 vpngroup && \
    useradd -m -u 1000 -g 1000 vpnuser && \
    chown -R vpnuser:vpngroup /app

# Switch to non-root user
USER vpnuser

# Expose HTTPS port
EXPOSE 443

# Run Flask application with Gunicorn (production WSGI server)
CMD ["gunicorn", "--bind", "0.0.0.0:443", "--certfile", "/app/certs/cert.pem", "--keyfile", "/app/certs/key.pem", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
