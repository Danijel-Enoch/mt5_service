#!/bin/bash

source /scripts/02-common.sh

log_message "RUNNING" "05-install-python.sh"

install_python_msi() {
    local msi_dir="/tmp/python-msi"
    local msi_order="core dev exe lib path pip"
    local msifile msi_exit msi_log

    mkdir -p "$msi_dir"
    cd "$msi_dir" || return 1

    for msifile in $msi_order; do
        log_message "INFO" "Installing Python MSI: ${msifile}.msi"
        if ! wget -q -O "${msifile}.msi" "${python_msi_base}/${msifile}.msi"; then
            log_message "ERROR" "Failed to download ${msifile}.msi"
            cd - >/dev/null || true
            return 1
        fi
        msi_log="/tmp/python-msi-${msifile}.log"
        WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" \
            ${wine_executable} msiexec /i "${msi_dir}/${msifile}.msi" /qn \
            "TARGETDIR=${python_msi_target}" ALLUSERS=1 \
            > "${msi_log}" 2>&1
        msi_exit=$?
        wait_wine
        if [ "$msi_exit" -ne 0 ]; then
            log_message "WARN" "msiexec returned ${msi_exit} for ${msifile}.msi"
            tail -10 "${msi_log}" >> /var/log/mt5_setup.log 2>/dev/null || true
        fi
        rm -f "${msifile}.msi" "${msi_log}"
    done

    cd - >/dev/null || true
    return 0
}

if is_wine_python_installed; then
    resolve_wine_python_exe
    log_message "INFO" "Python is already installed in Wine at ${wine_python_exe}."
else
    log_message "INFO" "Installing Python ${python_version} in Wine via MSI to ${python_msi_target}..."
    install_python_msi
    if ! is_wine_python_installed; then
        log_message "ERROR" "Python verification failed after MSI install."
        exit 1
    fi
    resolve_wine_python_exe
    log_message "INFO" "Python installed in Wine at ${wine_python_exe}."
fi

log_message "INFO" "Linux Python version: $(python3 --version 2>&1)"
log_message "INFO" "Wine Python version: $(wine_python --version 2>&1)"

log_message "INFO" "Wine Python installation details:"
wine_python -c "import sys; print(f'Python version: {sys.version}')" >> /var/log/mt5_setup.log 2>&1
wine_python -c "import sys; print(f'Python executable: {sys.executable}')" >> /var/log/mt5_setup.log 2>&1

log_message "INFO" "Installed packages in Wine Python environment:"
wine_python -m pip list >> /var/log/mt5_setup.log 2>&1
