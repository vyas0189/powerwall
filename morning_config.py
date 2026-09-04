"""AWS Lambda handler for the morning Tesla Powerwall configuration.

Shared logic lives in netzero_client; this module only defines the
schedule-specific configuration payload.
"""

from netzero_client import run

# Applied at 8:55 AM, just before the "Twelve Hour Power 24" free period (9 PM - 9 AM)
# ends. Grid power costs ~27.7c/kWh until 9 PM, so the battery carries the house: grid
# charging off, reserve dropped to 20%. Exports are disabled outright: the site has no export
# agreement, so the system must never backfeed the grid.
MORNING_CONFIG = {
    "backup_reserve_percent": 20,
    "operational_mode": "autonomous",
    "energy_exports": "never",
    "grid_charging": False,
}


def lambda_handler(event, context):
    """AWS Lambda handler for morning Tesla Powerwall configuration"""
    return run(MORNING_CONFIG, "morning")
