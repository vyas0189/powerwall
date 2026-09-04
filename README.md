# Powerwall Scheduler

Automated Tesla energy management using AWS Lambda and the NetZero Developer API with enterprise-grade security and automated CI/CD pipeline.

## Overview

This project provides two scheduled Lambda functions that automatically configure your Tesla energy system:

- **Morning Job (8:55 AM Central Time daily)**: Sets backup reserve to 20%, autonomous mode, grid exports disabled, grid charging disabled — the battery carries the house through the expensive daytime window
- **Evening Job (9:05 PM Central Time daily)**: Sets backup reserve to 100%, autonomous mode, grid exports disabled, grid charging enabled — the battery refills on free overnight power

**Daylight Saving Time Support**: The scheduler automatically adjusts between CDT (Central Daylight Time) and CST (Central Standard Time) to ensure jobs run at the correct local time year-round.

## 🏆 Features

- ✅ **Serverless Architecture**: AWS Lambda + EventBridge scheduling
- ✅ **Enterprise Security**: KMS encryption, IAM least privilege, secret scanning
- ✅ **Automated CI/CD**: GitHub Actions with manual approval gates
- ✅ **Infrastructure as Code**: Terraform with S3 state backend
- ✅ **Dependency Management**: Automated security updates via Dependabot
- ✅ **Code Quality**: Linting, formatting, security scanning with CodeQL

## Prerequisites

- AWS account with appropriate permissions
- GitHub repository with Actions enabled
- Python 3.12+
- NetZero Developer API key and Site ID

## GitHub Actions Deployment (Recommended)

### 1. Fork/Clone Repository

```bash
git clone <your-repo-url>
cd netzero-api
```

### 2. Configure GitHub Secrets

Go to your repository's Settings → Secrets and variables → Actions, and add:

- `SITE_ID` - Your Tesla site ID

> **AWS authentication uses GitHub OIDC, not long-lived keys.** The deploy
> workflow assumes the `netzero-github-actions-oidc` IAM role (created in
> `terraform-bootstrap/oidc.tf`, trust scoped to this repo's `main` branch), so
> no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets are needed — if they
> still exist from an older setup, delete them and deactivate the matching IAM
> access keys.

> The NetZero API key is **not** a GitHub secret either. It lives in an SSM
> Parameter Store SecureString that the Lambdas read at runtime, so it never
> enters the Lambda env config or Terraform state (see below). The old `API_KEY`
> GitHub secret can be removed.

### Store the NetZero API key (one-time)

Create the SSM SecureString **before** the first deploy (it is managed
out-of-band, not by Terraform, so the secret value never enters Terraform
state):

```bash
aws ssm put-parameter \
  --name "/netzero/api_key" \
  --type SecureString \
  --value "<your-netzero-api-key>" \
  --region us-east-1
```

To rotate the key later, re-run with `--overwrite`. The parameter name is
configurable via the `api_key_param_name` Terraform variable.

### 3. Deploy

Push to main branch or manually trigger the workflow:

```bash
git add .
git commit -m "Deploy Tesla scheduler"
git push origin main
```

The GitHub Actions workflow will:
- ✅ Run CI checks (linting, formatting, Terraform validation)
- ✅ Plan infrastructure changes with full Terraform output
- ✅ Require manual approval for production deployment
- ✅ Deploy Lambda functions with automatic dependency packaging
- ✅ Apply infrastructure changes with zero downtime

### 4. Monitor Deployment

Check the Actions tab in your GitHub repository to monitor deployment progress and view logs. The pipeline includes:
- **CI Pipeline**: Runs on all PRs and pushes
- **Security Scanning**: CodeQL analysis and secret detection
- **Manual Approval**: Production environment gate for safety

## Manual Deployment Options

### Terraform (Local)

First store the NetZero API key in SSM (one-time, see "Store the NetZero API key"
above) — it is **not** a Terraform variable, so it never enters TF state. Then:

```bash
cd terraform
terraform init
terraform plan -var="site_id=$NET_ZERO_SITE_ID" -out=tfplan
terraform apply tfplan
```


## 📁 Project Structure

### Core Files
- `morning_config.py` - Lambda function for morning configuration
- `evening_config.py` - Lambda function for evening configuration  
- `requirements.txt` - Python dependencies (automatically managed)

### Infrastructure
- `terraform/main.tf` - Terraform infrastructure as code (AWS provider v6.9)
- `terraform-bootstrap/main.tf` - S3 state backend setup

### CI/CD & Security
- `.github/workflows/deploy.yml` - Production deployment pipeline
- `.github/workflows/ci.yml` - Code quality and security checks
- `.github/dependabot.yml` - Automated dependency updates
- `SECURITY.md` - Security policy and vulnerability reporting
- `CLAUDE.md` - Repo conventions, rate-plan rationale, and deploy gotchas for AI assistants

## Testing

Functions are tested automatically in the GitHub Actions pipeline. For manual testing:

```bash
aws lambda invoke --function-name netzero-morning-config --payload '{}' response.json
aws lambda invoke --function-name netzero-evening-config --payload '{}' response.json
```

## Configuration Details

### Morning Configuration (8:55 AM Central Time)
- Backup Reserve: 20%
- Operational Mode: Autonomous
- Energy Exports: Never (no backfeed to the grid)
- Grid Charging: Disabled

### Evening Configuration (9:05 PM Central Time)
- Backup Reserve: 100%
- Operational Mode: Autonomous
- Energy Exports: Never (no backfeed to the grid)
- Grid Charging: Enabled

### Why These Times

The schedule is tuned to the **Direct Energy "Twelve Hour Power 24"** plan (CenterPoint service
area, in effect since 2026-09-04):

| Window | Energy | TDU delivery | Effective rate |
|---|---|---|---|
| 9:00 PM – 9:00 AM ("Designated Free Period") | 0¢/kWh | waived | **free** |
| 9:00 AM – 9:00 PM | 22.7042¢/kWh | 4.9811¢/kWh | **≈27.7¢/kWh** |

So the strategy is: grid-charge to 100% overnight while power is free, then run the house off
the battery all day. The jobs fire five minutes *inside* the safe side of each boundary — 8:55 AM
(grid charging is already off before billing starts) and 9:05 PM (grid charging is only enabled
once power is free). Don't "round" them to 9:00/9:00; the buffers absorb scheduler and NetZero
API latency, which would otherwise mean charging the battery at 27.7¢/kWh.

Exports are set to `never` in both configs: the site has no export agreement, so the system must
not backfeed the grid at all. When the battery is full and solar exceeds house load, the
inverter curtails instead of exporting. This is a hard constraint — `pv_only` would still allow
solar to flow out, and the plan has no buyback that would make that worth doing anyway.

### Daylight Saving Time Handling

Each job is a single EventBridge schedule with `schedule_expression_timezone =
"America/Chicago"`, so AWS resolves the cron expression against Central local time and shifts
automatically between CDT and CST. Each job fires exactly once per day, including on DST
transition days — no duplicate runs and no UTC offsets to maintain.

## Reliability & Alerting

### Retry

Failures of the NetZero API call are retried at two layers:

- **In-code retry**: each Lambda retries the API request up to 3 times with
  exponential backoff (2s, 4s) to ride out transient errors within a single run.
- **Scheduler retry**: if the Lambda invocation still fails, EventBridge
  Scheduler retries the invocation (up to 2 attempts, within a 1-hour window).

Runs that exhaust all retries are sent to an SQS **dead-letter queue**
(`netzero-scheduler-dlq`, 14-day retention) for inspection or replay.

### Failure alerts

A CloudWatch alarm on each Lambda's `Errors` metric publishes to the
`netzero-alerts` SNS topic, which emails `var.alert_email` (defaults to the
project owner). You also receive a recovery ("OK") notification when the next
run succeeds.

> **One-time setup:** After the first deploy, AWS sends a subscription
> confirmation email to the alert address. **You must click the confirmation
> link** before any alerts are delivered. Override the address with
> `-var="alert_email=you@example.com"`.

## Monitoring

View logs in AWS CloudWatch:
- `/aws/lambda/netzero-morning-config`
- `/aws/lambda/netzero-evening-config`

## 🔐 Security Features

This project implements enterprise-grade security:

### Infrastructure Security
- **KMS Encryption**: Lambda environment variables encrypted at rest
- **S3 State Encryption**: Terraform state encrypted with versioning
- **IAM Least Privilege**: Minimal required permissions for all roles
- **VPC Ready**: Architecture supports private networking

### GitHub Security
- **Secret Scanning**: Automated detection with push protection
- **CodeQL Analysis**: Static security analysis for all code
- **Dependabot**: Automated security updates for dependencies
- **Branch Protection**: Required reviews and status checks
- **SHA-pinned Actions**: Supply chain attack prevention

### CI/CD Security
- **Manual Approval Gates**: Production deployments require approval
- **Separate PR/Push Workflows**: No secrets exposed to pull requests
- **Terraform State Locking**: Prevents concurrent modifications
- **Encrypted Secrets**: All sensitive data properly secured

## 🚀 GitHub Actions Workflow

### CI Pipeline (Runs on all PRs)
- Code linting and formatting (flake8, black)
- Python syntax validation
- Terraform format and validation
- Security scanning with CodeQL

### Deploy Pipeline (Main branch only)
- Full Terraform plan with state backend
- Manual approval for production changes
- Automated Lambda packaging and deployment
- Infrastructure updates with zero downtime

**Triggers:**
- Push to main branch (full deployment)
- Pull requests (validation only)
- Manual workflow dispatch

## 🔗 API Reference

Uses NetZero Developer API: https://docs.netzero.energy/docs/tesla/API.html

## 📊 Monitoring & Observability

### AWS CloudWatch
- `/aws/lambda/netzero-morning-config` - Morning job logs
- `/aws/lambda/netzero-evening-config` - Evening job logs

### GitHub Actions
- **Deployment Status**: Actions tab shows all pipeline runs
- **Security Alerts**: Security tab for vulnerability reports
- **Dependency Updates**: PRs automatically created by Dependabot

## 🛠️ Maintenance

This project is designed for minimal maintenance:
- **Automated Updates**: Dependabot handles security patches
- **Self-Monitoring**: CloudWatch logs capture all executions
- **Version Pinning**: SHA-locked actions prevent supply chain issues
- **State Management**: Terraform state automatically backed up to S3