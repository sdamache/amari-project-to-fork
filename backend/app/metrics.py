"""
Prometheus metrics for application monitoring.

This module provides custom metrics that are exposed via a /metrics endpoint
for Cloud Run to scrape and send to GCP Cloud Monitoring.
"""

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Document processing counter
# Tracks total documents processed with status label (success/error)
document_processing_total = Counter(
    "document_processing_total",
    "Total number of documents processed",
    ["status"],  # Labels: success, error
)

# LLM extraction duration histogram
# Tracks how long LLM extraction takes in seconds
llm_extraction_duration_seconds = Histogram(
    "llm_extraction_duration_seconds",
    "Time spent on LLM extraction in seconds",
    buckets=[0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 60.0, 120.0],
)

# File upload bytes counter
# Tracks total bytes uploaded across all files
file_upload_bytes = Counter(
    "file_upload_bytes",
    "Total bytes uploaded",
)


def get_metrics() -> bytes:
    """
    Generate Prometheus metrics in text format.

    Returns:
        bytes: Prometheus-formatted metrics data.
    """
    return generate_latest()


def get_metrics_content_type() -> str:
    """
    Get the content type for Prometheus metrics.

    Returns:
        str: The content type string for Prometheus metrics.
    """
    return CONTENT_TYPE_LATEST
