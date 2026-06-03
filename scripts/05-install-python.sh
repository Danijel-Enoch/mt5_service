#!/bin/bash

source /scripts/02-common.sh

log_message "RUNNING" "05-install-python.sh"

install_python_msi() {
    local msi_dir="/tmp/python-msi"
    local target='C:\Program Files\Python39'
    local msi_order="ucrt core dev exe lib path pip"

    mkdir -p "$msi_dir"
    cd "$msi_dir" || return 1

    for msifile in $msi_order; do
        log_message "INFO" "Installing Python MSI: ${msifile}.msi"
        if ! wget -q -O "${msifile}.msi" "${python_msi_base}/${msifile}.msi"; then
            log_message "ERROR" "Failed to download ${msifile}.msi"
            cd - >/dev/null || true
            return 1
        fi
        if ! WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" \
            ${wine_executable} msiexec /i "${msi_dir}/${msifile}.msi" /qn "TARGETDIR=${target}" ALLUSERS=1; then
            log_message "ERROR" "msiexec failed for ${msifile}.msi"
            rm -f "${msifile}.msi"
            cd - >/dev/null || true
            return 1
        fi
        rm -f "${msifile}.msi"
    done

    wait_wine
    cd - >/dev/null || true
    return 0
}

if is_wine_python_installed; then
    log_message "INFO" "Python is already installed in Wine at ${wine_python_exe}."
else
    log_message "INFO" "Installing Python ${python_version} in Wine via MSI..."
    if ! install_python_msi; then
        log_message "ERROR" "Python MSI installation failed."
        exit 1
    fi
    if ! is_wine_python_installed; then
        log_message "ERROR" "Python verification failed: ${wine_python_exe} missing or not runnable."
        exit 1
    fi
    log_message "INFO" "Python installed in Wine at ${wine_python_exe}."
fi

log_message "INFO" "Linux Python version: $(python3 --version 2>&1)"
log_message "INFO" "Wine Python version: $(wine_python --version 2>&1)"

log_message "INFO" "Wine Python installation details:"
wine_python -c "import sys; print(f'Python version: {sys.version}')" >> /var/log/mt5_setup.log 2>&1
wine_python -c "import sys; print(f'Python executable: {sys.executable}')" >> /var/log/mt5_setup.log 2>&1

log_message "INFO" "Installed packages in Wine Python environment:"
wine_python -m pip list >> /var/log/mt5_setup.log 2>&1
