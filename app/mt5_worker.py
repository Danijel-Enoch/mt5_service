"""
Single-threaded MT5 job queue. All MT5 calls run in one worker thread so the
terminal is never used concurrently. Request handlers submit work via run_mt5()
and block until the worker returns the result.
"""
import logging
import os
import queue
import threading
from typing import Any, Callable, Optional

logger = logging.getLogger(__name__)

DEFAULT_MT5_TERMINAL_PATH = (
    "/config/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"
)

_job_queue: Optional[queue.Queue] = None
_worker_started = threading.Event()
_start_lock = threading.Lock()


def _initialize_mt5() -> bool:
    import MetaTrader5 as mt5

    path = os.environ.get("MT5_TERMINAL_PATH", DEFAULT_MT5_TERMINAL_PATH)
    portable = os.environ.get("MT5_PORTABLE", "false").lower() == "true"
    kwargs = {"path": path, "portable": portable}
    if not mt5.initialize(**kwargs):
        logger.warning(
            "MT5 worker: initialize() returned False (path=%s); continuing anyway.",
            path,
        )
        return False
    return True


def _worker_loop() -> None:
    if not _initialize_mt5():
        pass
    _worker_started.set()
    while True:
        job = _job_queue.get()
        if job is None:
            break
        try:
            result = job["fn"]()
            job["result"] = result
            job["exception"] = None
        except Exception as e:
            job["result"] = None
            job["exception"] = e
        job["event"].set()


def _ensure_worker() -> None:
    global _job_queue
    if _job_queue is not None:
        return
    with _start_lock:
        if _job_queue is not None:
            return
        _job_queue = queue.Queue()
        t = threading.Thread(target=_worker_loop, daemon=True)
        t.start()
        _worker_started.wait(timeout=10)
        if not _worker_started.is_set():
            logger.warning("MT5 worker start event not set within 10s.")


def start_worker() -> None:
    """Start the MT5 worker thread (idempotent). Call at app creation if desired."""
    _ensure_worker()


def run_mt5(fn: Callable[[], Any], timeout: Optional[float] = None) -> Any:
    """
    Run the callable on the MT5 worker thread and return its result.
    Raises the same exception the callable raised if it fails.
    If timeout is set and exceeded, raises TimeoutError.
    """
    _ensure_worker()
    job = {"fn": fn, "result": None, "exception": None, "event": threading.Event()}
    _job_queue.put(job)
    if not job["event"].wait(timeout=timeout):
        logger.error("run_mt5: timeout waiting for result")
        raise TimeoutError("MT5 request timed out")
    if job["exception"] is not None:
        raise job["exception"]
    return job["result"]
