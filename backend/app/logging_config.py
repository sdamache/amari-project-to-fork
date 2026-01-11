"""
GCP Cloud Logging compatible structured JSON logging configuration.

This module provides:
- GCPJSONFormatter: Formats logs as JSON matching GCP Cloud Logging format
- setup_logging(): Configures the root logger with GCP-compatible output
- RequestLoggingMiddleware: ASGI middleware for HTTP request/response logging
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Optional

# GCP severity levels mapping from Python logging levels
# https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#LogSeverity
SEVERITY_MAP = {
    logging.DEBUG: "DEBUG",
    logging.INFO: "INFO",
    logging.WARNING: "WARNING",
    logging.ERROR: "ERROR",
    logging.CRITICAL: "CRITICAL",
}


class GCPJSONFormatter(logging.Formatter):
    """
    Formatter that outputs JSON matching GCP Cloud Logging structured format.

    Output format:
    {
        "severity": "INFO",
        "message": "Log message",
        "timestamp": "2024-01-15T10:30:00.000000Z",
        "serviceContext": {"service": "backend"},
        "logging.googleapis.com/trace": "projects/PROJECT/traces/TRACE_ID"  # if available
    }
    """

    def __init__(self, service_name: str = "backend", project_id: Optional[str] = None):
        super().__init__()
        self.service_name = service_name
        self.project_id = project_id or os.getenv("GCP_PROJECT_ID", "")

    def format(self, record: logging.LogRecord) -> str:
        # Base log entry
        log_entry = {
            "severity": SEVERITY_MAP.get(record.levelno, "DEFAULT"),
            "message": record.getMessage(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "serviceContext": {
                "service": self.service_name,
            },
        }

        # Add source location for debugging
        log_entry["logging.googleapis.com/sourceLocation"] = {
            "file": record.pathname,
            "line": record.lineno,
            "function": record.funcName,
        }

        # Add trace ID if available (set by middleware from X-Cloud-Trace-Context header)
        trace_id = getattr(record, "trace_id", None)
        if trace_id and self.project_id:
            log_entry["logging.googleapis.com/trace"] = f"projects/{self.project_id}/traces/{trace_id}"
        elif trace_id:
            # Include trace_id even without project_id for local debugging
            log_entry["trace_id"] = trace_id

        # Add httpRequest if present (set by RequestLoggingMiddleware)
        http_request = getattr(record, "httpRequest", None)
        if http_request:
            log_entry["httpRequest"] = http_request

        # Add any extra fields passed via the 'extra' parameter
        extra_fields = getattr(record, "extra_fields", None)
        if extra_fields and isinstance(extra_fields, dict):
            log_entry.update(extra_fields)

        # Add exception info if present
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_entry, default=str)


def setup_logging(
    service_name: str = "backend",
    level: int = logging.INFO,
    project_id: Optional[str] = None,
) -> logging.Logger:
    """
    Configure the root logger with GCP-compatible JSON formatting.

    Args:
        service_name: Name of the service (shown in logs)
        level: Logging level (default: INFO)
        project_id: GCP project ID for trace correlation

    Returns:
        Configured root logger
    """
    # Get or create root logger
    logger = logging.getLogger()
    logger.setLevel(level)

    # Remove existing handlers to avoid duplicates
    logger.handlers.clear()

    # Create console handler with JSON formatter
    handler = logging.StreamHandler()
    handler.setLevel(level)
    handler.setFormatter(GCPJSONFormatter(service_name=service_name, project_id=project_id))

    logger.addHandler(handler)

    # Also configure uvicorn loggers to use our format
    for uvicorn_logger_name in ["uvicorn", "uvicorn.error", "uvicorn.access"]:
        uvicorn_logger = logging.getLogger(uvicorn_logger_name)
        uvicorn_logger.handlers.clear()
        uvicorn_logger.addHandler(handler)
        uvicorn_logger.propagate = False  # Prevent duplicate logs

    return logger


class RequestLoggingMiddleware:
    """
    ASGI middleware that logs HTTP requests with GCP-compatible format.

    Logs include:
    - HTTP method, path, status code
    - Request latency in milliseconds
    - Trace ID from X-Cloud-Trace-Context header (if present)
    """

    def __init__(self, app, logger: Optional[logging.Logger] = None):
        self.app = app
        self.logger = logger or logging.getLogger(__name__)

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        start_time = time.perf_counter()

        # Extract trace ID from X-Cloud-Trace-Context header
        # Format: TRACE_ID/SPAN_ID;o=TRACE_TRUE
        trace_id = None
        headers = dict(scope.get("headers", []))
        trace_header = headers.get(b"x-cloud-trace-context", b"").decode("utf-8", errors="ignore")
        if trace_header:
            trace_id = trace_header.split("/")[0]

        # Capture response status code
        status_code = 500  # Default to 500 in case of unhandled error

        async def send_wrapper(message):
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            # Calculate latency
            latency_ms = (time.perf_counter() - start_time) * 1000
            latency_seconds = latency_ms / 1000

            # Build path with query string
            path = scope.get("path", "/")
            query_string = scope.get("query_string", b"").decode("utf-8", errors="ignore")
            if query_string:
                path = f"{path}?{query_string}"

            method = scope.get("method", "UNKNOWN")

            # Create httpRequest object for GCP format
            http_request = {
                "requestMethod": method,
                "requestUrl": path,
                "status": status_code,
                "latency": f"{latency_seconds:.3f}s",
            }

            # Determine log level based on status code
            if status_code >= 500:
                level = logging.ERROR
            elif status_code >= 400:
                level = logging.WARNING
            else:
                level = logging.INFO

            # Create log record with extra attributes
            extra = {
                "httpRequest": http_request,
            }
            if trace_id:
                extra["trace_id"] = trace_id

            self.logger.log(
                level,
                f"{method} {path} {status_code} {latency_ms:.0f}ms",
                extra=extra,
            )


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance with the given name.

    Use this to get loggers for individual modules:
        logger = get_logger(__name__)
        logger.info("Processing document", extra={"extra_fields": {"doc_id": "123"}})

    Args:
        name: Logger name (typically __name__)

    Returns:
        Logger instance
    """
    return logging.getLogger(name)
