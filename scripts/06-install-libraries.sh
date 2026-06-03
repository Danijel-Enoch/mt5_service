#!/bin/bash

source /scripts/02-common.sh

log_message "RUNNING" "06-install-libraries.sh"

if ! is_wine_python_installed; then
    log_message "ERROR" "Wine Python is not installed; cannot install libraries."
    exit 1
fi

log_message "INFO" "Installing MetaTrader5 library and dependencies in Windows"
if ! is_wine_python_package_installed "MetaTrader5"; then
    if ! wine_python -m pip install --no-cache-dir -r /app/requirements.txt >> /var/log/mt5_setup.log 2>&1; then
        log_message "ERROR" "Failed to install Python dependencies in Wine."
        exit 1
    fi
    log_message "INFO" "Python dependencies installed in Wine."
else
    log_message "INFO" "MetaTrader5 library is already installed in Wine."
fi
