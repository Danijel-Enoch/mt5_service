#!/bin/bash

# Set variables
mt5setup_url="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
mt5file="/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
python_version="3.9.13"
python_msi_base="https://www.python.org/ftp/python/${python_version}/amd64"
python_msi_target='C:\Python39'
wine_executable="wine64"
metatrader_version="5.0.36"
mt5server_port=18812

# Defaults when runuser drops Docker ENV (see 01-start.sh)
WINEPREFIX="${WINEPREFIX:-/config/.wine}"
WINEARCH="${WINEARCH:-win64}"
wine_python_exe=""
export WINEPREFIX WINEARCH
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-abc}"
export DISPLAY="${DISPLAY:-:0}"

resolve_wine_python_exe() {
    local candidate
    for candidate in \
        "${WINEPREFIX}/drive_c/Program Files/Python39/python.exe" \
        "${WINEPREFIX}/drive_c/Python39/python.exe"; do
        if [ -f "$candidate" ]; then
            wine_python_exe="$candidate"
            return 0
        fi
    done
    wine_python_exe="${WINEPREFIX}/drive_c/Python39/python.exe"
    return 1
}

# Function to show messages
log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" >> /var/log/mt5_setup.log
}

wait_wine() {
    wineserver -w 2>/dev/null || true
    sleep 1
}

wine_python() {
    resolve_wine_python_exe || return 1
    ${wine_executable} "${wine_python_exe}" "$@"
}

is_wine_python_installed() {
    resolve_wine_python_exe || return 1
    wine_python --version >/dev/null 2>&1
}

# Function to check if a Python package is installed in Wine
is_wine_python_package_installed() {
    wine_python -c "import pkg_resources; pkg_resources.require('$1')" 2>/dev/null
    return $?
}

# Function to check if a Python package is installed in Linux
is_python_package_installed() {
    python3 -c "import pkg_resources; pkg_resources.require('$1')" 2>/dev/null
    return $?
}

# Mute Unnecessary Wine Errors
export WINEDEBUG=-all,err-toolbar,fixme-all

# Ensure a 64-bit Wine prefix (32-bit prefix breaks MT5 on WINEARCH=win64)
ensure_wine64_prefix() {
    if [ -f "${WINEPREFIX}/system.reg" ]; then
        if grep -q '"#arch"="win32"' "${WINEPREFIX}/system.reg" 2>/dev/null; then
            if [ -e "$mt5file" ]; then
                log_message "ERROR" "Wine prefix is 32-bit but MT5 is installed; manual migration required."
                return 1
            fi
            log_message "WARN" "Removing incompatible 32-bit Wine prefix at ${WINEPREFIX}"
            rm -rf "${WINEPREFIX}"
        fi
    fi
    if [ ! -d "${WINEPREFIX}" ]; then
        log_message "INFO" "Initializing 64-bit Wine prefix at ${WINEPREFIX}"
        WINEARCH=win64 WINEPREFIX="${WINEPREFIX}" ${wine_executable} wineboot --init
        sleep 5
        WINEARCH=win64 WINEPREFIX="${WINEPREFIX}" ${wine_executable} wineboot --init
        sleep 3
    fi
}
