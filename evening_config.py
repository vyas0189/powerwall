import json
import os
import requests
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """AWS Lambda handler for evening Tesla Powerwall configuration"""

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
        "backup_reserve_percent": 100,
        "operational_mode": "autonomous",
        "energy_exports": "pv_only",
        "grid_charging": True,
    }

    try:
        logger.info(f"Applying evening configuration: {config}")
        response = requests.post(url, json=config, headers=headers, timeout=30)
        response.raise_for_status()

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
        logger.error(f"Failed to apply evening configuration: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps(
                {"error": f"Failed to apply evening configuration: {str(e)}"}
            ),
        }
