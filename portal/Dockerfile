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

# Note: Running as root is required for Easy-RSA operations on PKI directory
# The portal needs write access to /etc/openvpn/easy-rsa/pki owned by root

# Expose HTTPS port
EXPOSE 443

# Run Flask application
CMD ["python", "app.py"]
