#!/bin/bash

source /scripts/02-common.sh

log_message "RUNNING" "05-install-python.sh"
setup_echo "Running Wine Python setup..."

install_wine_python() {
    clear_stale_wine_installers

    if is_wine_python_installed; then
        resolve_wine_python_exe
        log_message "INFO" "Python is already installed in Wine at ${wine_python_exe}."
        setup_echo "Python already installed at ${wine_python_exe}"
        return 0
    fi

    if [ ! -d "${python_template_dir}" ]; then
        log_message "ERROR" "Python template missing at ${python_template_dir}."
        setup_echo "ERROR: Python template missing from container image."
        return 1
    fi

    local target_dir="${WINEPREFIX}/drive_c/Python39"
    log_message "INFO" "Seeding Python ${python_version} from image template..."
    setup_echo "Copying prebuilt Python ${python_version} into Wine prefix..."

    mkdir -p "${WINEPREFIX}/drive_c"
    rm -rf "${target_dir}"
    cp -a "${python_template_dir}" "${target_dir}"
    setup_echo "Python files copied; verifying Wine Python..."

    if ! is_wine_python_installed; then
        log_message "ERROR" "Python verification failed after copying template."
        setup_echo "ERROR: Python copy completed but verification failed."
        return 1
    fi

    resolve_wine_python_exe
    log_message "INFO" "Python installed in Wine at ${wine_python_exe}."
    setup_echo "Python ready at ${wine_python_exe}"

    log_message "INFO" "Linux Python version: $(python3 --version 2>&1)"
    log_message "INFO" "Wine Python version: $(wine_python --version 2>&1)"

    log_message "INFO" "Wine Python installation details:"
    wine_python -c "import sys; print(f'Python version: {sys.version}')" >> /var/log/mt5_setup.log 2>&1
    wine_python -c "import sys; print(f'Python executable: {sys.executable}')" >> /var/log/mt5_setup.log 2>&1

    log_message "INFO" "Installed packages in Wine Python environment:"
    wine_python -m pip list >> /var/log/mt5_setup.log 2>&1
}

install_wine_python || exit 1
