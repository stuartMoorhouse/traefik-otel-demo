#!/bin/bash
set -e

echo "========================================="
echo "Starting Application Deployment"
echo "========================================="

PROJECT_DIR="/home/ubuntu/traefik-otel-demo"
cd $PROJECT_DIR

# Read environment variables from .env
source .env

# ============================================================================
# Create Flask Application
# ============================================================================
echo "Creating Flask application..."

cat > app.py <<'PYEOF'
from flask import Flask, jsonify
import random
import time
import os
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)

# Prometheus metrics
metrics = PrometheusMetrics(app)

# Cities and weather conditions
CITIES = ["stockholm", "london", "paris", "tokyo", "newyork", "berlin", "sydney", "toronto"]
CONDITIONS = ["sunny", "cloudy", "rainy", "snowy", "windy", "foggy"]

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

@app.route('/weather/<city>')
def weather(city):
    # Simulate latency
    time.sleep(random.uniform(0.1, 0.5))

    # Simulate errors 10% of the time
    if random.random() < 0.1:
        return jsonify({"error": "Service temporarily unavailable"}), 503

    # Return weather data
    temperature = random.randint(-10, 35)
    condition = random.choice(CONDITIONS)

    return jsonify({
        "city": city.lower(),
        "temperature": temperature,
        "condition": condition,
        "timestamp": time.time()
    }), 200

@app.route('/metrics-custom')
def metrics_custom():
    return jsonify({
        "requests_today": random.randint(1000, 10000),
        "active_users": random.randint(50, 500)
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

# ============================================================================
# Create Requirements
# ============================================================================
echo "Creating requirements.txt..."

cat > requirements.txt <<'REQEOF'
flask==3.0.0
elastic-opentelemetry[flask]==0.4.0
prometheus-flask-exporter==0.23.0
REQEOF

# ============================================================================
# Create Dockerfile
# ============================================================================
echo "Creating Dockerfile..."

cat > Dockerfile <<'DOCKEREOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["opentelemetry-instrument", "flask", "run", "--host=0.0.0.0"]
DOCKEREOF

# ============================================================================
# Create Traefik Configuration
# ============================================================================
echo "Creating Traefik configuration..."

cat > traefik.yml <<'TRAEFIKEOF'
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
    addRoutersLabels: true

tracing:
  otlp:
    http:
      endpoint: "http://edot-collector:4318"
TRAEFIKEOF

# ============================================================================
# Create EDOT Collector Configuration
# ============================================================================
echo "Creating EDOT Collector configuration..."

# Export variables for envsubst
export ELASTIC_ENDPOINT
export ELASTIC_USERNAME
export ELASTIC_PASSWORD
export ELASTIC_API_KEY

# Copy template and substitute environment variables
envsubst < edot-collector-config.yaml.template > edot-collector-config.yaml

# ============================================================================
# Create Prometheus Configuration
# ============================================================================
echo "Creating Prometheus configuration..."

cat > prometheus.yml <<'PROMEOF'
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'edot-collector'
    static_configs:
      - targets: ['edot-collector:8888']

  - job_name: 'flask-app'
    static_configs:
      - targets: ['flask-app:5000']
    metrics_path: '/metrics'

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']

# Forward all scraped metrics to EDOT Collector
remote_write:
  - url: http://edot-collector:9090/api/v1/write
    queue_config:
      capacity: 10000
      max_shards: 5
      min_shards: 1
      max_samples_per_send: 3000
      batch_send_deadline: 5s
PROMEOF

# ============================================================================
# Create Docker Compose
# ============================================================================
echo "Creating docker-compose.yml..."

cat > docker-compose.yml <<'COMPOSEEOF'
services:
  flask-app:
    build: .
    container_name: flask-app
    ports:
      - "5000:5000"
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://edot-collector:4318
      - OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
      - OTEL_TRACES_EXPORTER=otlp
      - OTEL_METRICS_EXPORTER=otlp
      - OTEL_LOGS_EXPORTER=otlp
      - OTEL_SERVICE_NAME=weather-api
      - OTEL_RESOURCE_ATTRIBUTES=deployment.environment=demo,service.version=1.0.0
      - ELASTIC_OTEL_LOG_LEVEL=debug
    depends_on:
      - edot-collector
    networks:
      - demo-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.flask.rule=PathPrefix(`/api`)"
      - "traefik.http.services.flask.loadbalancer.server.port=5000"

  traefik:
    image: traefik:v3.2
    container_name: traefik
    command:
      - "--configFile=/etc/traefik/traefik.yml"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
    depends_on:
      - edot-collector
    networks:
      - demo-network

  edot-collector:
    image: elastic/elastic-agent:9.2.0
    container_name: edot-collector
    deploy:
      resources:
        limits:
          memory: 1.5G
    restart: unless-stopped
    command: ["--config", "/etc/otelcol-config.yml"]
    user: "0:0"
    volumes:
      - /:/hostfs:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./edot-collector-config.yaml:/etc/otelcol-config.yml:ro
    ports:
      - "4317:4317"   # OTLP gRPC receiver
      - "4318:4318"   # OTLP HTTP receiver
      - "8888:8888"   # Prometheus metrics (EDOT's own metrics)
      - "13133:13133" # Health check endpoint
      # Note: Port 9090 (Prometheus remote_write receiver) is not exposed to host
      # It's only used for internal Docker network communication with Prometheus container
    environment:
      - ELASTIC_AGENT_OTEL=true
      - ELASTIC_ENDPOINT=${ELASTIC_ENDPOINT}
      - ELASTIC_API_KEY=${ELASTIC_API_KEY}
      - HOST_FILESYSTEM=/hostfs
      - STORAGE_DIR=/usr/share/elastic-agent
    env_file:
      - .env
    networks:
      - demo-network

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"  # Prometheus UI - view metrics at http://ec2-ip:9090
    depends_on:
      - edot-collector
    networks:
      - demo-network

networks:
  demo-network:
    driver: bridge

volumes:
  prometheus-data:
COMPOSEEOF

# ============================================================================
# Verify API Key Exists
# ============================================================================
echo "Verifying API key..."

# Reload .env in case it was updated by create-api-key.sh
source .env

if [ "$ELASTIC_API_KEY" = "PLACEHOLDER" ] || [ -z "$ELASTIC_API_KEY" ]; then
  echo "✗ Error: API key not found in .env file"
  echo "The create-api-key.sh script should have been run before this script."
  exit 1
fi

echo "✓ API key found in .env"

# ============================================================================
# Build and Start Services
# ============================================================================
echo "Building Docker images..."
docker-compose build --no-cache

echo "Starting services..."
docker-compose up -d

echo "Waiting for services to be healthy..."
sleep 30

# ============================================================================
# Verify Services
# ============================================================================
echo "========================================="
echo "Service Status:"
echo "========================================="
docker-compose ps

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo "Flask API: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5000"
echo "Traefik Dashboard: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "========================================="
