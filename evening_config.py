"""AWS Lambda handler for the evening Tesla Powerwall configuration.

Shared logic lives in netzero_client; this module only defines the
schedule-specific configuration payload.
"""

from netzero_client import run

EVENING_CONFIG = {
    "backup_reserve_percent": 100,
    "operational_mode": "autonomous",
    "energy_exports": "pv_only",
    "grid_charging": True,
}


def lambda_handler(event, context):
    """AWS Lambda handler for evening Tesla Powerwall configuration"""
    return run(EVENING_CONFIG, "evening")
