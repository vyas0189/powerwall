"""Shared NetZero API client logic for the morning/evening Powerwall Lambdas.

Both schedule handlers (`morning_config.py`, `evening_config.py`) are identical
except for the configuration payload they apply, so the common work — fetching
the API key from SSM, validating the site id, and POSTing with retry/backoff —
lives here and is invoked via `run(config, label)`.
"""

import json
import os
import re
import time
import logging
from datetime import datetime

import boto3
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Retry configuration for transient NetZero API failures
MAX_RETRIES = 3
BACKOFF_BASE_SECONDS = 2
REQUEST_TIMEOUT_SECONDS = 15

# Tesla/NetZero site ids are opaque alphanumeric identifiers; restrict to a safe
# charset so a malformed value can't reshape the request path.
SITE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]+$")

# The NetZero API key is stored as an SSM Parameter Store SecureString and
# fetched at runtime, so it never lives in the Lambda env config or TF state.
API_KEY_PARAM = os.getenv("API_KEY_PARAM", "/netzero/api_key")
_ssm_client = boto3.client("ssm")
_api_key_cache = None


def get_api_key():
    """Fetch (and cache across warm invocations) the NetZero API key from the
    SSM Parameter Store SecureString."""
    global _api_key_cache
    if _api_key_cache is None:
        try:
            response = _ssm_client.get_parameter(
                Name=API_KEY_PARAM, WithDecryption=True
            )
        except Exception:
            # Don't surface the raw boto traceback; log a generic message and
            # re-raise so the invocation still fails and triggers the alarm /
            # DLQ path. The parameter name is intentionally omitted to keep any
            # credential-shaped value out of the logs.
            logger.error("Failed to read the NetZero API key from SSM Parameter Store")
            raise
        _api_key_cache = response["Parameter"]["Value"]
    return _api_key_cache


def post_with_retry(url, config, headers):
    """POST the config to the NetZero API, retrying transient failures with
    exponential backoff. Raises the last RequestException if all attempts fail."""
    last_exception = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.post(
                url, json=config, headers=headers, timeout=REQUEST_TIMEOUT_SECONDS
            )
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            last_exception = e
            logger.warning(f"Attempt {attempt}/{MAX_RETRIES} failed: {str(e)}")
            if attempt < MAX_RETRIES:
                sleep_seconds = BACKOFF_BASE_SECONDS**attempt
                logger.info(f"Retrying in {sleep_seconds}s")
                time.sleep(sleep_seconds)
    raise last_exception


def run(config, label):
    """Apply `config` to the configured Tesla site via the NetZero API.

    `label` ("morning"/"evening") is used only for log/response messages.
    Returns an API Gateway-style dict on success/validation failure; re-raises a
    RequestException when all retries are exhausted so the Lambda is marked
    failed (incrementing the Errors metric that drives the CloudWatch alarm).
    """
    site_id = os.getenv("SITE_ID")

    if not site_id:
        logger.error("SITE_ID environment variable is required")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing SITE_ID environment variable"}),
        }

    if not SITE_ID_PATTERN.match(site_id):
        logger.error("SITE_ID has an invalid format")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Invalid SITE_ID format"}),
        }

    api_key = get_api_key()

    url = f"https://api.netzero.energy/api/v1/{site_id}/config"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}

    try:
        logger.info(f"Applying {label} configuration: {config}")
        post_with_retry(url, config, headers)

        logger.info(f"{label.capitalize()} configuration applied successfully")

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": (
                        f"{label.capitalize()} Tesla configuration applied "
                        f"successfully at {datetime.now().isoformat()}"
                    ),
                    "config": config,
                }
            ),
        }

    except requests.exceptions.RequestException as e:
        # Re-raise so the Lambda invocation is marked as failed. This increments
        # the Lambda Errors metric (which triggers the CloudWatch alarm / SNS
        # alert) and signals EventBridge Scheduler to retry and, on exhaustion,
        # send the event to the dead-letter queue.
        logger.error(
            f"Failed to apply {label} configuration after {MAX_RETRIES} attempts: "
            f"{str(e)}"
        )
        raise
