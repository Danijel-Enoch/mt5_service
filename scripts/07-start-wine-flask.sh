#!/bin/bash

source /scripts/02-common.sh

log_message "RUNNING" "07-start-wine-flask.sh"

log_message "INFO" "Starting Flask server in Wine environment..."

if ! is_wine_python_installed; then
    log_message "ERROR" "Wine Python is not installed; cannot start Flask."
    exit 1
fi

if [ -z "$MT5_API_PORT" ] && [ -f /tmp/mt5_env.sh ]; then
    MT5_API_PORT=$(grep '^MT5_API_PORT=' /tmp/mt5_env.sh 2>/dev/null | cut -d'=' -f2)
fi

if [ -z "$MT5_API_PORT" ]; then
    MT5_API_PORT=5001
    log_message "WARN" "MT5_API_PORT not set; defaulting to ${MT5_API_PORT}"
fi

log_message "INFO" "MT5_API_PORT is set to: $MT5_API_PORT"
export MT5_API_PORT

wine_python /app/app.py >> /var/log/mt5_setup.log 2>&1 &
FLASK_PID=$!

for _ in $(seq 1 30); do
    if nc -z 127.0.0.1 "${MT5_API_PORT}" 2>/dev/null; then
        log_message "INFO" "Flask server in Wine started successfully (PID ${FLASK_PID}, port ${MT5_API_PORT})."
        exit 0
    fi
    if ! ps -p "$FLASK_PID" > /dev/null 2>&1; then
        log_message "ERROR" "Flask process exited before binding to port ${MT5_API_PORT}."
        exit 1
    fi
    sleep 1
done

log_message "ERROR" "Flask server did not listen on port ${MT5_API_PORT} within 30 seconds."
exit 1
