I want to create a 2 cron job that runs every day using the NetZero Developer API.

First Job: Every day at 6:45 AM: Set backup reserve to: 25%; Set operational mode to: Time-Based Control; Set energy exports to: Everything (solar and battery); Set grid charging to: Disabled.

Second Job: Every day at 9:15 PM: Set backup reserve to: 100%; Set operational mode to: Time-Based Control; Set energy exports to: Solar only; Set grid charging to: Enabled.

NetZero Developer API: https://docs.netzero.energy/docs/tesla/API.html

I should be able to deploy this in any platform

use python

load API_KEY & SITE_ID from envrionment