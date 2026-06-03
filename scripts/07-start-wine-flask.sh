#!/bin/bash

source /scripts/02-common.sh

log_message "RUNNING" "07-start-wine-flask.sh"

log_message "INFO" "Starting Flask server in Wine environment..."

# MT5_API_PORT should be available from /tmp/mt5_env.sh (sourced in 01-start.sh)
# If not, try reading from /tmp/mt5_env.sh directly
if [ -z "$MT5_API_PORT" ] && [ -f /tmp/mt5_env.sh ]; then
    MT5_API_PORT=$(grep '^MT5_API_PORT=' /tmp/mt5_env.sh 2>/dev/null | cut -d'=' -f2)
fi

if [ -z "$MT5_API_PORT" ]; then
    MT5_API_PORT=5001
    log_message "WARN" "MT5_API_PORT not set; defaulting to ${MT5_API_PORT}"
fi

log_message "INFO" "MT5_API_PORT is set to: $MT5_API_PORT"

# Export it for Wine/Python
export MT5_API_PORT

# Run the Flask app using Wine's Python
$wine_executable python /app/app.py &

FLASK_PID=$!

# Give the server some time to start
sleep 5

# Check if the Flask server is running
if ps -p $FLASK_PID > /dev/null; then
    log_message "INFO" "Flask server in Wine started successfully with PID $FLASK_PID."
else
    log_message "ERROR" "Failed to start Flask server in Wine."
    exit 1
fi