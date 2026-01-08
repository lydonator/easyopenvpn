#!/usr/bin/env python3
from flask import Flask, session, redirect, render_template, request, url_for, jsonify, send_file, abort
import bcrypt
import os
import subprocess
import re
import json
from pathlib import Path

app = Flask(__name__)

# Load configuration from environment variables
app.secret_key = os.environ.get('SESSION_SECRET', 'changeme-generate-random-secret')
app.config['PERMANENT_SESSION_LIFETIME'] = 3600

# Configuration
PORTAL_PASSWORD_HASH = os.environ.get('PORTAL_PASSWORD_HASH', '')
SERVER_IP = os.environ.get('SERVER_IP', 'Unknown')
EASYRSA_DIR = '/etc/openvpn/easy-rsa'
CLIENT_DIR = '/app/data/clients'
CERT_FILE = '/app/certs/cert.pem'
KEY_FILE = '/app/certs/key.pem'

# Generate self-signed certificate if not exists
def generate_ssl_cert():
    """Generate self-signed SSL certificate for HTTPS"""
    if os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE):
        return

    print("Generating self-signed SSL certificate...")
    os.makedirs('/app/certs', exist_ok=True)

    # Generate certificate valid for 365 days
    cmd = [
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', KEY_FILE,
        '-out', CERT_FILE,
        '-days', '365',
        '-nodes',
        '-subj', f'/CN={SERVER_IP}'
    ]

    try:
        subprocess.run(cmd, check=True, capture_output=True)
        os.chmod(KEY_FILE, 0o600)
        os.chmod(CERT_FILE, 0o644)
        print(f"✓ SSL certificate generated: {CERT_FILE}")
    except subprocess.CalledProcessError as e:
        print(f"Failed to generate SSL certificate: {e}")
        raise

# Login required decorator
def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'error': 'Authentication required'}), 401
        return f(*args, **kwargs)
    return decorated_function

@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        password = request.form.get('password', '')

        try:
            # Verify password against bcrypt hash from environment
            if bcrypt.checkpw(password.encode(), PORTAL_PASSWORD_HASH.encode()):
                session['authenticated'] = True
                session.permanent = True
                return redirect(url_for('dashboard'))
            else:
                error = 'Invalid password'
        except Exception as e:
            error = 'Authentication error'

    return render_template('login.html', error=error)

@app.route('/dashboard')
def dashboard():
    if not session.get('authenticated'):
        return redirect(url_for('login'))

    return render_template('dashboard.html', server_ip=SERVER_IP)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/api/clients', methods=['GET'])
@login_required
def list_clients():
    """List all VPN clients"""
    try:
        os.makedirs(CLIENT_DIR, exist_ok=True)

        clients = []
        client_files = Path(CLIENT_DIR).glob('*.ovpn')

        for ovpn_file in client_files:
            if ovpn_file.is_file():
                name = ovpn_file.stem
                size = ovpn_file.stat().st_size
                clients.append({
                    'name': name,
                    'file': str(ovpn_file),
                    'size': size
                })

        return jsonify({'clients': clients}), 200

    except Exception as e:
        return jsonify({'error': f'Failed to list clients: {str(e)}'}), 500

@app.route('/api/clients', methods=['POST'])
@login_required
def create_client():
    """Create a new VPN client"""
    try:
        client_name = request.json.get('client_name', '').strip()

        # Validate client name (alphanumeric with dashes/underscores only)
        if not client_name:
            return jsonify({'error': 'Client name is required'}), 400

        if not re.match(r'^[a-zA-Z0-9_-]+$', client_name):
            return jsonify({'error': 'Invalid client name. Use only letters, numbers, dashes, and underscores.'}), 400

        # Check if client already exists
        os.makedirs(CLIENT_DIR, exist_ok=True)
        client_file = f'{CLIENT_DIR}/{client_name}.ovpn'
        if os.path.exists(client_file):
            return jsonify({'error': f'Client {client_name} already exists'}), 400

        # Generate client certificate using Easy-RSA
        os.chdir(EASYRSA_DIR)

        # Build client certificate request and key
        subprocess.run(
            ['./easyrsa', '--batch', 'build-client-full', client_name, 'nopass'],
            check=True,
            capture_output=True,
            timeout=30
        )

        # Read certificate files
        ca_cert = Path(f'{EASYRSA_DIR}/pki/ca.crt').read_text()
        client_cert = Path(f'{EASYRSA_DIR}/pki/issued/{client_name}.crt').read_text()
        client_key = Path(f'{EASYRSA_DIR}/pki/private/{client_name}.key').read_text()
        ta_key = Path(f'{EASYRSA_DIR}/pki/ta.key').read_text()

        # Create client configuration file
        ovpn_config = f"""client
dev tun
proto udp
remote {SERVER_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
verb 3
key-direction 1

<ca>
{ca_cert}</ca>

<cert>
{client_cert}</cert>

<key>
{client_key}</key>

<tls-auth>
{ta_key}</tls-auth>
"""

        # Write client configuration
        Path(client_file).write_text(ovpn_config)
        os.chmod(client_file, 0o644)

        return jsonify({
            'success': True,
            'message': f'Client {client_name} created successfully',
            'client_name': client_name,
            'file': client_file
        }), 200

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Client creation timed out'}), 500
    except subprocess.CalledProcessError as e:
        return jsonify({'error': f'Failed to generate client certificate: {e.stderr.decode()}'}), 500
    except Exception as e:
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500

@app.route('/api/clients/<client_name>', methods=['DELETE'])
@login_required
def delete_client(client_name):
    """Delete a VPN client and revoke certificate"""
    try:
        # Validate client name
        if not re.match(r'^[a-zA-Z0-9_-]+$', client_name):
            return jsonify({'error': 'Invalid client name'}), 400

        # Check if client exists
        client_file = f'{CLIENT_DIR}/{client_name}.ovpn'
        if not os.path.exists(client_file):
            return jsonify({'error': f'Client {client_name} does not exist'}), 400

        # Change to Easy-RSA directory
        os.chdir(EASYRSA_DIR)

        # Revoke client certificate
        subprocess.run(
            ['./easyrsa', '--batch', 'revoke', client_name],
            check=True,
            capture_output=True,
            timeout=30
        )

        # Regenerate CRL
        subprocess.run(
            ['./easyrsa', 'gen-crl'],
            check=True,
            capture_output=True,
            timeout=30
        )

        # Copy updated CRL to OpenVPN directory
        subprocess.run(
            ['cp', f'{EASYRSA_DIR}/pki/crl.pem', '/etc/openvpn/server/crl.pem'],
            check=True
        )

        # Remove client configuration file
        if os.path.exists(client_file):
            os.remove(client_file)

        return jsonify({
            'success': True,
            'message': f'Client {client_name} deleted successfully'
        }), 200

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Client deletion timed out'}), 500
    except subprocess.CalledProcessError as e:
        return jsonify({'error': f'Failed to delete client: {e.stderr.decode()}'}), 500
    except Exception as e:
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500

@app.route('/download/<client_name>')
@login_required
def download_client(client_name):
    """Download client configuration file"""
    try:
        # Validate client_name format to prevent path traversal
        if not re.match(r'^[a-zA-Z0-9_-]+$', client_name):
            abort(400)

        # Construct safe file path
        client_dir = Path(CLIENT_DIR)
        client_file = client_dir / f'{client_name}.ovpn'

        # Verify file exists
        if not client_file.exists():
            abort(404)

        # Verify the resolved path is still within client_dir (prevent traversal)
        if not str(client_file.resolve()).startswith(str(client_dir.resolve())):
            abort(403)

        # Send file with proper headers
        return send_file(
            str(client_file),
            mimetype='application/x-openvpn-profile',
            as_attachment=True,
            download_name=f'{client_name}.ovpn'
        )

    except Exception as e:
        abort(500)

if __name__ == '__main__':
    # Generate SSL certificate if needed
    generate_ssl_cert()

    # Start Flask app with HTTPS
    app.run(
        host='0.0.0.0',
        port=443,
        ssl_context=(CERT_FILE, KEY_FILE)
    )
