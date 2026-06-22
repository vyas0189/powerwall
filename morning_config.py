import json
import os
import time
import requests
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Retry configuration for transient NetZero API failures
MAX_RETRIES = 3
BACKOFF_BASE_SECONDS = 2
REQUEST_TIMEOUT_SECONDS = 15


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
    """AWS Lambda handler for morning Tesla Powerwall configuration"""

    api_key = os.getenv("API_KEY")
    site_id = os.getenv("SITE_ID")

    if not api_key or not site_id:
        logger.error("API_KEY and SITE_ID environment variables are required")
        return {
            "statusCode": 400,
            "body": json.dumps(
                {"error": "Missing API_KEY or SITE_ID environment variables"}
            ),
        }

    url = f"https://api.netzero.energy/api/v1/{site_id}/config"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}

    config = {
        "backup_reserve_percent": 20,
        "operational_mode": "autonomous",
        "energy_exports": "battery_ok",
        "grid_charging": False,
    }

    try:
        logger.info(f"Applying morning configuration: {config}")
        post_with_retry(url, config, headers)

        logger.info("Morning configuration applied successfully")

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": f"Morning Tesla configuration applied successfully at {datetime.now().isoformat()}",
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
            f"Failed to apply morning configuration after {MAX_RETRIES} attempts: {str(e)}"
        )
        raise
