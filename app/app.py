import logging
import os
from flask import Flask
from dotenv import load_dotenv
import MetaTrader5 as mt5
from flasgger import Swagger
from werkzeug.middleware.proxy_fix import ProxyFix
from swagger import swagger_config
from mt5_worker import start_worker

# Import routes
from routes.health import health_bp
from routes.symbol import symbol_bp
from routes.data import data_bp
from routes.position import position_bp
from routes.order import order_bp
from routes.history import history_bp
from routes.error import error_bp
from routes.account import account_bp
from routes.internal import internal_bp

load_dotenv()
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['PREFERRED_URL_SCHEME'] = 'https'

swagger = Swagger(app, config=swagger_config)

# Register blueprints
app.register_blueprint(health_bp)
app.register_blueprint(symbol_bp)
app.register_blueprint(data_bp)
app.register_blueprint(position_bp)
app.register_blueprint(order_bp)
app.register_blueprint(history_bp)
app.register_blueprint(error_bp)
app.register_blueprint(account_bp)
app.register_blueprint(internal_bp)

app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

# Start MT5 worker thread so all MT5 calls run serially
start_worker()

if __name__ == '__main__':
    if not mt5.initialize():
        logger.error("Failed to initialize MT5.")
    
    # MT5_API_PORT must be set in environment (via docker-compose env_file)
    mt5_api_port = os.environ.get('MT5_API_PORT')
    if not mt5_api_port:
        raise ValueError("MT5_API_PORT environment variable is required but not set.")
    
    app.run(host='0.0.0.0', port=int(mt5_api_port))