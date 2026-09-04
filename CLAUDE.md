# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

Two AWS Lambdas that push a Powerwall configuration to the NetZero Developer API on a daily
schedule. That's the whole product — there is no server, no state, no database. The interesting
part is *when* the jobs run and *why* those values are set.

- `netzero_client.py` — all shared logic: SSM key fetch (cached), `SITE_ID` validation, POST with
  retry/backoff. `run(config, label)` is the single entry point.
- `morning_config.py` / `evening_config.py` — nothing but a config dict and a `lambda_handler`.
  Any behavior change belongs in `netzero_client.py`, not duplicated across the two.
- `terraform/` — Lambdas, EventBridge schedules, IAM, SNS/CloudWatch alerts, SQS DLQ.
- `terraform-bootstrap/` — S3 state backend and the GitHub OIDC role. **Applied out-of-band by an
  admin, not by CI**, with local state.

## The electricity plan drives everything

The site is on **Direct Energy "Twelve Hour Power 24"** (CenterPoint, since 2026-09-04):

| Window | Effective rate |
|---|---|
| 9:00 PM – 9:00 AM ("Designated Free Period") | **free** (0¢ energy, TDU delivery waived) |
| 9:00 AM – 9:00 PM | **≈27.7¢/kWh** (22.7042¢ energy + 4.9811¢ TDU) |

Hence the strategy: grid-charge to 100% overnight while power is free, then run the house off the
battery all day. The jobs fire at **8:55 AM** and **9:05 PM** Central, five minutes on the safe
side of each boundary.

**Do not "clean up" those times to 9:00/9:00.** The asymmetric buffers are deliberate: the morning
job must disable grid charging *before* billing starts, and the evening job must enable it *after*
power is free. Rounding them risks charging the battery at 27.7¢/kWh on any scheduler or API
latency. Likewise, `energy_exports` is `never` in both configs because the site has no export
agreement and must not backfeed the grid — this is a hard constraint, not an optimization, so
do not "restore" `pv_only` to recover curtailed solar. If the plan changes,
update the times, the configs, the README "Why These Times" section, and the config assertions in
`test_netzero_client.py` together.

## Conventions

- Comments explain *why* (usually a rate-plan or reliability reason), not what the code does.
  Match the existing terse docstring style; don't add narration.
- Secrets never enter Terraform state, the Lambda env, or git. The NetZero API key lives in an SSM
  SecureString (`/netzero/api_key`) created out-of-band and read at runtime.
- Timezone handling is AWS's job: one schedule per Lambda with
  `schedule_expression_timezone = "America/Chicago"`. Never hardcode UTC times or add
  DST-transition special cases.
- Failures must stay loud. `run()` re-raises on exhausted retries so the Lambda is marked failed —
  that increments the `Errors` metric behind the CloudWatch alarm → SNS email, and lets the
  Scheduler retry into the DLQ. Don't swallow exceptions to make a run "succeed".

## Before you commit

Run what CI runs (`.github/workflows/ci.yml`):

```bash
python3 -m pytest -q
python3 -m black --check .
python3 -m flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
python3 -m bandit -r morning_config.py evening_config.py netzero_client.py
terraform -chdir=terraform fmt -check -diff
```

## Deploy gotchas

- **The OIDC deploy role can't grant itself permissions.** `terraform/iam.tf` is applied *by* the
  pipeline; the role's trust policy and control-plane inline policy live in
  `terraform-bootstrap/oidc.tf` and must be applied separately by an admin
  (`cd terraform-bootstrap && terraform apply -target=aws_iam_role_policy.oidc_control_plane`).
  A new permission needed *in order to plan/apply* goes in the bootstrap file.
- **Lambda zips are built by a `null_resource` `local-exec`** that only re-runs on source-hash
  change, while the apply job applies a saved plan on a fresh runner. `deploy.yml` has an explicit
  "Build Lambda packages" step in the apply job for exactly this reason — don't remove it.
- Log groups are **imported**, not created (`terraform/imports.tf`); Lambda creates them on first
  invocation.
- Editing `morning_config.py` or `evening_config.py` changes its `filemd5`, so Terraform will
  rebuild and redeploy that zip. Expected, not a bug.
