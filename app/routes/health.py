import logging
import os

import MetaTrader5 as mt5
from flask import Blueprint, jsonify
from flasgger import swag_from

from cache import get as cache_get, set as cache_set
from mt5_worker import run_mt5
from routes.internal import get_account_session

health_bp = Blueprint('health', __name__)
logger = logging.getLogger(__name__)
HEALTH_CACHE_KEY = ("health",)
HEALTH_TTL = 2

@health_bp.route('/health')
@swag_from({
    'tags': ['Health'],
    'responses': {
        200: {
            'description': 'Health check successful',
            'schema': {
                'type': 'object',
                'properties': {
                    'status': {'type': 'string'},
                    'mt5_connected': {'type': 'boolean'},
                    'mt5_initialized': {'type': 'boolean'}
                }
            }
        }
    }
})
def health_check():
    """
    Health Check Endpoint
    ---
    description: Check the health status of the application and MT5 connection.
    responses:
      200:
        description: Health check successful
    """
    cached = cache_get(HEALTH_CACHE_KEY)
    if cached is not None:
        return jsonify(cached), 200
    try:
        initialized = run_mt5(lambda: mt5.initialize() if mt5 is not None else False)
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        initialized = False
    account_id, server, connected = get_account_session()
    body = {
        "status": "healthy",
        "mt5_connected": mt5 is not None,
        "mt5_initialized": initialized,
        "account_id": account_id,
        "connected": connected,
        "server": server,
        "worker_name": os.environ.get("MT5_WORKER_NAME"),
    }
    cache_set(HEALTH_CACHE_KEY, body, HEALTH_TTL)
    return jsonify(body), 200

@health_bp.route('/terminal_info', methods=['GET'])
@swag_from({
    'tags': ['Health'],
    'responses': {
        200: {
            'description': 'Terminal information retrieved successfully.',
            'schema': {
                'type': 'object',
                'properties': {
                    'name': {'type': 'string'},
                    'company': {'type': 'string'},
                    'path': {'type': 'string'},
                    'build': {'type': 'integer'},
                    'connected': {'type': 'boolean'},
                    'trade_allowed': {'type': 'boolean'},
                    'ping_last': {'type': 'integer'}
                }
            }
        },
        400: {
            'description': 'Failed to retrieve terminal information.'
        },
        500: {
            'description': 'Internal server error.'
        }
    }
})
def get_terminal_info():
    """
    Get Terminal Information
    ---
    description: Retrieve terminal information including connection status and capabilities.
    """
    try:
        terminal_info = run_mt5(mt5.terminal_info)
        if terminal_info is None:
            error_code, error_str = run_mt5(mt5.last_error)
            return jsonify({
                "error": "Failed to get terminal information",
                "mt5_error": error_str,
                "error_code": error_code
            }), 400
        
        # Convert to dictionary
        terminal_dict = terminal_info._asdict()
        
        return jsonify(terminal_dict), 200
    
    except Exception as e:
        logger.error(f"Error in get_terminal_info: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500