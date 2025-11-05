#!/bin/bash

echo "======================================="
echo "Traffic Generation with Traefik Restarts"
echo "Use Case 1: Counter Reset Demonstration"
echo "======================================="
echo ""

FLASK_URL="http://localhost:5000/weather"
CITIES=("stockholm" "london" "paris" "tokyo" "newyork" "berlin")
RESTART_COUNT=3

for restart in $(seq 1 $RESTART_COUNT); do
    echo ""
    echo "=== Cycle $restart of $RESTART_COUNT ==="
    echo ""
    
    # Generate traffic for 30 seconds
    echo "[Cycle $restart] Generating traffic for 30 seconds..."
    END_TIME=$((SECONDS+30))
    REQUEST_COUNT=0
    
    while [ $SECONDS -lt $END_TIME ]; do
        # Pick a random city
        CITY=${CITIES[$RANDOM % ${#CITIES[@]}]}
        
        # Make request
        RESPONSE=$(curl -s -w "\n%{http_code}" ${FLASK_URL}/${CITY} 2>/dev/null)
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            ((REQUEST_COUNT++))
            echo -ne "\r[Cycle $restart] Requests sent: $REQUEST_COUNT (Last: $CITY - ✓)    "
        else
            echo -ne "\r[Cycle $restart] Requests sent: $REQUEST_COUNT (Last: $CITY - ✗ $HTTP_CODE)    "
        fi
        
        # Small delay between requests
        sleep 0.3
    done
    
    echo ""
    echo "[Cycle $restart] Generated $REQUEST_COUNT requests"
    
    # Don't restart on the last cycle
    if [ $restart -lt $RESTART_COUNT ]; then
        echo "[Cycle $restart] Restarting Traefik container..."
        docker restart traefik > /dev/null 2>&1
        
        echo "[Cycle $restart] Waiting for Traefik to come back up (10s)..."
        sleep 10
        
        # Verify Traefik is up
        if docker ps | grep -q traefik; then
            echo "[Cycle $restart] ✓ Traefik restarted successfully"
        else
            echo "[Cycle $restart] ✗ Warning: Traefik may not be running"
        fi
        
        echo "[Cycle $restart] Waiting 5s before next cycle..."
        sleep 5
    fi
done

echo ""
echo "======================================="
echo "Traffic Generation Complete!"
echo "======================================="
echo ""
echo "Summary:"
echo "- Total cycles: $RESTART_COUNT"
echo "- Traefik restarts: $((RESTART_COUNT - 1))"
echo ""
echo "What to check in Kibana:"
echo "1. Look for Traefik counter metrics (traefik_entrypoint_requests_total)"
echo "2. Notice counter values reset to 0 after each restart"
echo "3. Use ES|QL rate() function to handle counter resets properly"
echo ""
echo "ES|QL Query Example:"
echo "FROM metrics-otel-demo"
echo "| WHERE metricset.name == \"traefik\" AND metric.name == \"traefik.entrypoint.requests.total\""
echo "| EVAL rate_value = rate(metric.value)"
echo "| STATS total_rate = SUM(rate_value) BY @timestamp"
