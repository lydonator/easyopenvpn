#!/bin/bash
set -e

echo "🔐 Checking SSL certificates..."

CERT_FILE="/app/certs/cert.pem"
KEY_FILE="/app/certs/key.pem"

# Generate self-signed certificate if not exists
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "📝 Generating self-signed SSL certificate..."
    mkdir -p /app/certs

    openssl req -x509 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -days 365 \
        -nodes \
        -subj "/CN=${SERVER_IP:-localhost}" \
        >/dev/null 2>&1

    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    echo "✅ SSL certificate generated"
else
    echo "✅ SSL certificates already exist"
fi

echo "🚀 Starting Gunicorn..."
exec gunicorn --bind 0.0.0.0:443 \
    --certfile "$CERT_FILE" \
    --keyfile "$KEY_FILE" \
    --access-logfile /dev/null \
    --error-logfile /dev/null \
    --log-level critical \
    app:app
