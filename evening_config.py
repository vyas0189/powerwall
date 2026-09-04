"""AWS Lambda handler for the evening Tesla Powerwall configuration.

Shared logic lives in netzero_client; this module only defines the
schedule-specific configuration payload.
"""

from netzero_client import run

# Applied at 9:05 PM, just after the "Twelve Hour Power 24" free period (9 PM - 9 AM)
# starts. Grid energy and TDU delivery are both free until 9 AM, so the grid runs the
# house and refills the battery: grid charging on, reserve at 100% so the pack is full
# when the expensive window opens. Exports stay disabled - the site cannot backfeed the grid.
EVENING_CONFIG = {
    "backup_reserve_percent": 100,
    "operational_mode": "autonomous",
    "energy_exports": "never",
    "grid_charging": True,
}


def lambda_handler(event, context):
    """AWS Lambda handler for evening Tesla Powerwall configuration"""
    return run(EVENING_CONFIG, "evening")
