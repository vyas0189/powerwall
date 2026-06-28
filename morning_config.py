"""AWS Lambda handler for the morning Tesla Powerwall configuration.

Shared logic lives in netzero_client; this module only defines the
schedule-specific configuration payload.
"""

from netzero_client import run

MORNING_CONFIG = {
    "backup_reserve_percent": 20,
    "operational_mode": "autonomous",
    "energy_exports": "battery_ok",
    "grid_charging": False,
}


def lambda_handler(event, context):
    """AWS Lambda handler for morning Tesla Powerwall configuration"""
    return run(MORNING_CONFIG, "morning")
