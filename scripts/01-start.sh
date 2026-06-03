#!/bin/bash

# Fix Wine prefix ownership (in case volume has wrong permissions) - only if running as root
if [ "$(id -u)" -eq 0 ]; then
    chown -R abc:abc /config/.wine 2>/dev/null || true
    chmod -R 755 /config/.wine 2>/dev/null || true
    
    # Save environment variables to a file that abc user can read.
    # runuser does not preserve Docker ENV (WINEPREFIX, WINEARCH, MT5_API_PORT, etc.).
    {
        echo "WINEPREFIX=${WINEPREFIX:-/config/.wine}"
        echo "WINEARCH=${WINEARCH:-win64}"
        echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-abc}"
        echo "DISPLAY=${DISPLAY:-:0}"
        echo "MT5_API_PORT=${MT5_API_PORT:-5001}"
        env | grep -E '^MT5_|^CUSTOM_|^PASSWORD=|^VNC_DOMAIN=|^API_DOMAIN=' || true
    } > /tmp/mt5_env.sh
    chmod 644 /tmp/mt5_env.sh
    chown abc:abc /tmp/mt5_env.sh
    
    # Run as abc user
    exec runuser -u abc -- "$0" "$@"
    exit 0
fi

# Source environment variables from file if available (when running as abc user)
if [ -f /tmp/mt5_env.sh ]; then
    set -a  # Automatically export all variables
    source /tmp/mt5_env.sh
    set +a
fi

# From here, we're running as abc user
source /scripts/02-common.sh

setup_echo "MT5 worker setup starting..."

run_setup_step() {
    local script=$1
    setup_echo "Step: ${script}"
    if ! "$script"; then
        log_message "ERROR" "Setup failed at ${script}"
        setup_echo "Setup failed at ${script} — see /var/log/mt5_setup.log"
        exit 1
    fi
}

run_all_setup() {
    run_setup_step /scripts/03-install-mono.sh
    run_setup_step /scripts/04-install-mt5.sh
    run_setup_step /scripts/05-install-python.sh
    run_setup_step /scripts/06-install-libraries.sh
    run_setup_step /scripts/07-start-wine-flask.sh
}

with_setup_lock run_all_setup

setup_echo "MT5 worker setup complete."
tail -f /dev/null
