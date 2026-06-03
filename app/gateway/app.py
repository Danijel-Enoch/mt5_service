import logging
import os

from dotenv import load_dotenv
from flask import Flask, Response, jsonify, request
from werkzeug.middleware.proxy_fix import ProxyFix

from registry import registry

load_dotenv()
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config["PREFERRED_URL_SCHEME"] = "https"
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

HOP_BY_HOP_HEADERS = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        "host",
        "content-length",
    }
)


def _proxy_to_worker(worker_url: str, path: str) -> Response:
    import httpx

    url = f"{worker_url.rstrip('/')}/{path.lstrip('/')}"
    headers = {
        k: v
        for k, v in request.headers
        if k.lower() not in HOP_BY_HOP_HEADERS
    }
    try:
        with httpx.Client(timeout=120.0) as client:
            resp = client.request(
                method=request.method,
                url=url,
                params=request.args,
                content=request.get_data(),
                headers=headers,
            )
    except httpx.RequestError as exc:
        logger.error("Proxy to %s failed: %s", url, exc)
        return jsonify({"error": "Worker unreachable", "detail": str(exc)}), 503

    excluded = HOP_BY_HOP_HEADERS | {"content-encoding", "content-length"}
    response_headers = [
        (k, v) for k, v in resp.headers.items() if k.lower() not in excluded
    ]
    return Response(resp.content, status=resp.status_code, headers=response_headers)


@app.route("/health", methods=["GET"])
def gateway_health():
    return jsonify(registry.aggregate_health()), 200


@app.route("/accounts", methods=["GET"])
def list_accounts():
    return jsonify({"accounts": registry.list_accounts()}), 200


@app.route("/accounts/<account_id>/health", methods=["GET"])
def account_health(account_id: str):
    worker_url = registry.get_worker_url(account_id)
    if not worker_url:
        return jsonify({
            "error": "Account not found or not connected",
            "account_id": account_id,
        }), 404
    return _proxy_to_worker(worker_url, "health")


@app.route("/accounts/<account_id>/<path:endpoint>", methods=[
    "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD",
])
def proxy_account(account_id: str, endpoint: str):
    worker_url = registry.get_worker_url(account_id)
    if not worker_url:
        return jsonify({
            "error": "Account not found or not connected",
            "account_id": account_id,
        }), 404
    return _proxy_to_worker(worker_url, endpoint)


if __name__ == "__main__":
    port = os.environ.get("MT5_API_PORT", "5001")
    registry.refresh(force=True)
    app.run(host="0.0.0.0", port=int(port))
