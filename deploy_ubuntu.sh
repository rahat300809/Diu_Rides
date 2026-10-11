#!/bin/bash
set -e

echo "========================================================"
echo "🚀 [DIU Ride] Starting Ubuntu Production Deployment"
echo "========================================================"

APP_DIR="/home/rahat/diu_ride"
SERVICE_NAME="diu-ride.service"

if [ -d "$APP_DIR" ]; then
    cd "$APP_DIR"
else
    echo "Using current directory: $(pwd)"
fi

echo "📥 1. Pulling latest production code from git..."
git pull origin main

echo "🐍 2. Ensuring Python environment dependencies..."
if [ -d "/home/rahat/diu_ride_env" ]; then
    /home/rahat/diu_ride_env/bin/pip install -r server/requirements.txt
else
    pip install -r server/requirements.txt
fi

echo "🔄 3. Restarting systemd production service..."
if command -v sudo &> /dev/null; then
    sudo systemctl restart "$SERVICE_NAME"
else
    systemctl restart "$SERVICE_NAME"
fi

echo "⏱️ 4. Waiting for daemon initialization..."
sleep 2

echo "🩺 5. Checking systemd service status..."
systemctl status "$SERVICE_NAME" --no-pager || true

echo "🌐 6. Testing local endpoint health..."
curl -s http://127.0.0.1:8001/ride/health || curl -s http://127.0.0.1:8001/health

echo ""
echo "========================================================"
echo "✅ [DIU Ride] Ubuntu Production Deployment Succeeded!"
echo "Public URL: https://servertest.eu.cc/ride"
echo "API Base:   https://servertest.eu.cc/ride/api"
echo "WebSocket:  wss://servertest.eu.cc/ride/ws"
echo "========================================================"
