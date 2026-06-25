import json
import os
import time
import logging
import boto3
import requests
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Retry configuration for transient NetZero API failures
MAX_RETRIES = 3
BACKOFF_BASE_SECONDS = 2
REQUEST_TIMEOUT_SECONDS = 15

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
        response = _ssm_client.get_parameter(Name=API_KEY_PARAM, WithDecryption=True)
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


def lambda_handler(event, context):
    """AWS Lambda handler for evening Tesla Powerwall configuration"""

    site_id = os.getenv("SITE_ID")

    if not site_id:
        logger.error("SITE_ID environment variable is required")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing SITE_ID environment variable"}),
        }

    api_key = get_api_key()

    url = f"https://api.netzero.energy/api/v1/{site_id}/config"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}

    config = {
        "backup_reserve_percent": 100,
        "operational_mode": "autonomous",
        "energy_exports": "pv_only",
        "grid_charging": True,
    }

    try:
        logger.info(f"Applying evening configuration: {config}")
        post_with_retry(url, config, headers)

        logger.info("Evening configuration applied successfully")

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": f"Evening Tesla configuration applied successfully at {datetime.now().isoformat()}",
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
            f"Failed to apply evening configuration after {MAX_RETRIES} attempts: {str(e)}"
        )
        raise
