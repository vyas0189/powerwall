# Powerwall Scheduler

Automated Tesla energy management using AWS Lambda and the NetZero Developer API with enterprise-grade security and automated CI/CD pipeline.

## Overview

This project provides two scheduled Lambda functions that automatically configure your Tesla energy system:

- **Morning Job (6:45 AM Central Time daily)**: Sets backup reserve to 20%, autonomous mode, battery exports enabled, grid charging disabled
- **Evening Job (9:15 PM Central Time daily)**: Sets backup reserve to 100%, autonomous mode, solar-only exports, grid charging enabled

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

- `AWS_ACCESS_KEY_ID` - Your AWS access key
- `AWS_SECRET_ACCESS_KEY` - Your AWS secret key  
- `API_KEY` - Your NetZero API key
- `SITE_ID` - Your Tesla site ID

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

```bash
export API_KEY="your_netzero_api_key"
export SITE_ID="your_tesla_site_id"

cd terraform
terraform init
terraform plan -var="api_key=$API_KEY" -var="site_id=$SITE_ID"
terraform apply -var="api_key=$API_KEY" -var="site_id=$SITE_ID"
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

## Testing

Functions are tested automatically in the GitHub Actions pipeline. For manual testing:

```bash
aws lambda invoke --function-name netzero-morning-config --payload '{}' response.json
aws lambda invoke --function-name netzero-evening-config --payload '{}' response.json
```

## Configuration Details

### Morning Configuration (6:45 AM Central Time)
- Backup Reserve: 20%
- Operational Mode: Autonomous
- Energy Exports: Battery OK (solar and battery)
- Grid Charging: Disabled

### Evening Configuration (9:15 PM Central Time)
- Backup Reserve: 100%
- Operational Mode: Autonomous
- Energy Exports: Solar Only
- Grid Charging: Enabled

### Daylight Saving Time Handling

The system automatically handles DST transitions using multiple EventBridge rules:

- **CDT Period (March 15-October 31)**: Schedules trigger at 11:45 AM UTC (morning) and 2:15 AM UTC (evening)
- **CST Period (November 8-February 28/29)**: Schedules trigger at 12:45 PM UTC (morning) and 3:15 AM UTC (evening)
- **March Transition Week (Days 8-14)**: Both UTC times trigger to cover the second Sunday when DST starts
- **November Transition Week (Days 1-7)**: Both UTC times trigger to cover the first Sunday when DST ends

This ensures your Tesla system is configured at exactly 6:45 AM and 9:15 PM Houston local time throughout the year, regardless of daylight saving time changes. During DST transition weeks, the job may run twice, but only the correct local time execution will apply the configuration.

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