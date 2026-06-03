import os

import MetaTrader5 as mt5
from flask import Blueprint, jsonify
from mt5_worker import run_mt5

internal_bp = Blueprint("internal", __name__)

DEFAULT_TERMINAL_PATH = (
    "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
)


def get_account_session():
    """Return account_id and server from active MT5 session, or nulls if not connected."""
    try:
        info = run_mt5(mt5.account_info)
    except Exception:
        return None, None, False
    if info is None:
        return None, None, False
    return str(info.login), info.server, True


@internal_bp.route("/internal/meta", methods=["GET"])
def internal_meta():
    account_id, server, connected = get_account_session()
    return jsonify({
        "account_id": account_id,
        "worker_name": os.environ.get("MT5_WORKER_NAME"),
        "connected": connected,
        "server": server,
        "mt5_terminal_path": os.environ.get("MT5_TERMINAL_PATH", DEFAULT_TERMINAL_PATH),
    }), 200
