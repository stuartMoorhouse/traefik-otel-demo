from flask import Flask, jsonify, request
import random
import time
import os
import logging
from prometheus_flask_exporter import PrometheusMetrics
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
metrics = PrometheusMetrics(app)

# Get tracer
tracer = trace.get_tracer(__name__)

# Cities and weather conditions
CITIES = ["stockholm", "london", "paris", "tokyo", "newyork", "berlin", "sydney", "toronto"]
CONDITIONS = ["sunny", "cloudy", "rainy", "snowy", "windy", "foggy"]

@app.route('/health')
def health():
    with tracer.start_as_current_span("health_check") as span:
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.route", "/health")
        logger.info("Health check requested")
        return jsonify({"status": "healthy"}), 200

@app.route('/weather/<city>')
def weather(city):
    with tracer.start_as_current_span("get_weather") as span:
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.route", "/weather/<city>")
        span.set_attribute("weather.city", city)

        logger.info("Weather request for city: %s", city)

        # Simulate latency
        time.sleep(random.uniform(0.1, 0.5))

        # Simulate errors 10% of the time
        if random.random() < 0.1:
            logger.error("Service error for city: %s", city)
            span.set_status(Status(StatusCode.ERROR, "Service temporarily unavailable"))
            span.set_attribute("error", True)
            return jsonify({"error": "Service temporarily unavailable"}), 503

        # Return weather data
        temperature = random.randint(-10, 35)
        condition = random.choice(CONDITIONS)

        span.set_attribute("weather.temperature", temperature)
        span.set_attribute("weather.condition", condition)

        logger.info("Returning weather for %s: %d°C, %s", city, temperature, condition)

        return jsonify({
            "city": city.lower(),
            "temperature": temperature,
            "condition": condition,
            "timestamp": time.time()
        }), 200

@app.route('/metrics-custom')
def metrics_custom():
    with tracer.start_as_current_span("custom_metrics") as span:
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.route", "/metrics-custom")
        logger.info("Custom metrics requested")
        return jsonify({
            "requests_today": random.randint(1000, 10000),
            "active_users": random.randint(50, 500)
        }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
