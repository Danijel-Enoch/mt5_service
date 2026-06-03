#!/bin/bash
# Build-time only: preinstall Wine Python into /opt/mt5-python-template (no MSI).
set -euo pipefail

PYTHON_VERSION="3.9.13"
TEMPLATE="/opt/mt5-python-template"
PY_DIR="${TEMPLATE}/drive_c/Python39"
EMBED_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-embed-amd64.zip"
GET_PIP_URL="https://bootstrap.pypa.io/pip/3.9/get-pip.py"

mkdir -p "${PY_DIR}" /tmp/runtime-abc
chown -R abc:abc "${TEMPLATE}" /tmp/runtime-abc

runuser -u abc -- bash <<EOF
set -euo pipefail
export WINEPREFIX="${TEMPLATE}"
export WINEARCH=win64
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-abc
export WINEDEBUG=-all,err-toolbar,fixme-all

if [ ! -f "\${WINEPREFIX}/system.reg" ]; then
    wine64 wineboot --init
    sleep 5
fi

cd /tmp
wget -q -O python-embed.zip "${EMBED_URL}"
rm -rf "${PY_DIR}"
mkdir -p "${PY_DIR}"
unzip -q -o python-embed.zip -d "${PY_DIR}"
rm -f python-embed.zip

# Enable pip/site-packages in embeddable layout.
sed -i 's/^#import site/import site/' "${PY_DIR}/python39._pth"
if ! grep -q 'site-packages' "${PY_DIR}/python39._pth"; then
    printf 'Lib\\site-packages\n' >> "${PY_DIR}/python39._pth"
fi

wget -q -O get-pip.py "${GET_PIP_URL}"
wine64 "${PY_DIR}/python.exe" get-pip.py
rm -f get-pip.py

wine64 "${PY_DIR}/python.exe" --version
wine64 "${PY_DIR}/python.exe" -m pip --version
wineserver -w 2>/dev/null || true
EOF

chown -R abc:abc "${TEMPLATE}"
echo "Wine Python template ready at ${PY_DIR}"
