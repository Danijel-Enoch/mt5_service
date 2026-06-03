"""
Poll MT5 worker containers and build account_id (login) -> worker base URL map.
"""
import logging
import os
import threading
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

import httpx

logger = logging.getLogger(__name__)

DEFAULT_WORKER_PORT = "5001"
REGISTRY_TTL_SECONDS = 30
META_TIMEOUT_SECONDS = 5


@dataclass
class WorkerEntry:
    worker_name: str
    worker_url: str
    vnc_port: Optional[int]
    vnc_host: Optional[str] = None
    account_id: Optional[str] = None
    connected: bool = False
    server: Optional[str] = None
    reachable: bool = False
    error: Optional[str] = None


@dataclass
class RegistrySnapshot:
    workers: List[WorkerEntry] = field(default_factory=list)
    route_map: Dict[str, str] = field(default_factory=dict)
    duplicate_account_ids: List[str] = field(default_factory=list)
    fetched_at: float = 0.0


class WorkerRegistry:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._snapshot = RegistrySnapshot()
        self._worker_hosts = self._parse_worker_hosts()
        self._worker_port = os.environ.get("MT5_WORKER_PORT", DEFAULT_WORKER_PORT)
        self._vnc_ports = self._parse_vnc_ports()
        self._vnc_base_domain = os.environ.get("VNC_BASE_DOMAIN", "").strip()

    @staticmethod
    def _parse_worker_hosts() -> List[str]:
        raw = os.environ.get("MT5_WORKER_HOSTS", "")
        return [h.strip() for h in raw.split(",") if h.strip()]

    def _parse_vnc_ports(self) -> Dict[str, int]:
        raw = os.environ.get("MT5_WORKER_VNC_PORTS", "")
        result: Dict[str, int] = {}
        for part in raw.split(","):
            part = part.strip()
            if not part or ":" not in part:
                continue
            name, port_str = part.rsplit(":", 1)
            try:
                result[name.strip()] = int(port_str.strip())
            except ValueError:
                logger.warning("Invalid VNC port mapping: %s", part)
        return result

    def _vnc_host_for_worker(self, worker_name: str) -> Optional[str]:
        if not self._vnc_base_domain:
            return None
        prefix = "mt5-worker-"
        if worker_name.startswith(prefix):
            index = worker_name[len(prefix):]
            if index:
                return f"w{index}.{self._vnc_base_domain}"
        return None

    def refresh(self, force: bool = False) -> RegistrySnapshot:
        with self._lock:
            age = time.monotonic() - self._snapshot.fetched_at
            if not force and self._snapshot.fetched_at and age < REGISTRY_TTL_SECONDS:
                return self._snapshot

        snapshot = self._fetch_snapshot()
        with self._lock:
            self._snapshot = snapshot
        return snapshot

    def _fetch_snapshot(self) -> RegistrySnapshot:
        workers: List[WorkerEntry] = []
        route_map: Dict[str, str] = {}
        login_counts: Dict[str, int] = {}

        for host in self._worker_hosts:
            worker_url = f"http://{host}:{self._worker_port}"
            entry = WorkerEntry(
                worker_name=host,
                worker_url=worker_url,
                vnc_port=self._vnc_ports.get(host),
                vnc_host=self._vnc_host_for_worker(host),
            )
            try:
                with httpx.Client(timeout=META_TIMEOUT_SECONDS) as client:
                    resp = client.get(f"{worker_url}/internal/meta")
                if resp.status_code != 200:
                    entry.error = f"meta HTTP {resp.status_code}"
                    workers.append(entry)
                    continue
                data = resp.json()
                entry.reachable = True
                entry.account_id = data.get("account_id")
                entry.connected = bool(data.get("connected"))
                entry.server = data.get("server")
                if entry.connected and entry.account_id:
                    login_counts[entry.account_id] = login_counts.get(entry.account_id, 0) + 1
                    route_map[entry.account_id] = worker_url
            except httpx.RequestError as exc:
                entry.error = str(exc)
                logger.warning("Worker %s unreachable: %s", host, exc)
            workers.append(entry)

        duplicate_account_ids = [
            login for login, count in login_counts.items() if count > 1
        ]
        if duplicate_account_ids:
            logger.error("Duplicate account IDs across workers: %s", duplicate_account_ids)
            for login in duplicate_account_ids:
                route_map.pop(login, None)

        return RegistrySnapshot(
            workers=workers,
            route_map=route_map,
            duplicate_account_ids=duplicate_account_ids,
            fetched_at=time.monotonic(),
        )

    def get_worker_url(self, account_id: str) -> Optional[str]:
        snapshot = self.refresh()
        return snapshot.route_map.get(account_id)

    def get_docs_worker(self) -> tuple[Optional[str], Optional[str]]:
        """Worker URL and account_id for root /apidocs (first routable, else first reachable)."""
        snapshot = self.refresh()
        for w in snapshot.workers:
            if w.account_id and w.account_id in snapshot.route_map:
                return w.worker_url, w.account_id
        for w in snapshot.workers:
            if w.reachable:
                return w.worker_url, w.account_id
        if self._worker_hosts:
            return f"http://{self._worker_hosts[0]}:{self._worker_port}", None
        return None, None

    def get_docs_worker_url(self) -> Optional[str]:
        worker_url, _ = self.get_docs_worker()
        return worker_url

    def list_accounts(self) -> List[dict]:
        snapshot = self.refresh()
        accounts = []
        for w in snapshot.workers:
            accounts.append({
                "account_id": w.account_id,
                "worker_name": w.worker_name,
                "connected": w.connected,
                "reachable": w.reachable,
                "server": w.server,
                "vnc_port": w.vnc_port,
                "vnc_host": w.vnc_host,
                "routable": w.account_id in snapshot.route_map if w.account_id else False,
                "error": w.error,
            })
        return accounts

    def aggregate_health(self) -> dict:
        snapshot = self.refresh()
        workers_health = []
        all_reachable = True
        any_connected = False
        for w in snapshot.workers:
            if not w.reachable:
                all_reachable = False
            if w.connected:
                any_connected = True
            workers_health.append({
                "worker_name": w.worker_name,
                "account_id": w.account_id,
                "connected": w.connected,
                "reachable": w.reachable,
                "error": w.error,
            })
        return {
            "status": "healthy" if all_reachable else "degraded",
            "gateway": "ok",
            "workers": workers_health,
            "any_connected": any_connected,
            "duplicate_account_ids": snapshot.duplicate_account_ids,
        }


registry = WorkerRegistry()
