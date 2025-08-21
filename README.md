# NetZero Tesla Scheduler

Automated Tesla energy management using AWS Lambda and the NetZero Developer API with GitHub Actions CI/CD pipeline.

## Overview

This project provides two scheduled Lambda functions that automatically configure your Tesla energy system:

- **Morning Job (6:45 AM CDT daily)**: Sets backup reserve to 25%, autonomous mode, battery exports enabled, grid charging disabled
- **Evening Job (9:15 PM CDT daily)**: Sets backup reserve to 100%, autonomous mode, solar-only exports, grid charging enabled

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
- ✅ Run Terraform format check
- ✅ Plan infrastructure changes
- ✅ Deploy Lambda functions with dependencies
- ✅ Test both functions automatically

### 4. Monitor Deployment

Check the Actions tab in your GitHub repository to monitor deployment progress and view logs.

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


## Files

- `morning_config.py` - Lambda function for morning configuration
- `evening_config.py` - Lambda function for evening configuration  
- `requirements.txt` - Python dependencies
- `terraform/main.tf` - Terraform infrastructure as code
- `.github/workflows/deploy.yml` - GitHub Actions CI/CD pipeline

## Testing

Functions are tested automatically in the GitHub Actions pipeline. For manual testing:

```bash
aws lambda invoke --function-name netzero-morning-config --payload '{}' response.json
aws lambda invoke --function-name netzero-evening-config --payload '{}' response.json
```

## Configuration Details

### Morning Configuration (6:45 AM CDT)
- Backup Reserve: 25%
- Operational Mode: Autonomous
- Energy Exports: Battery OK (solar and battery)
- Grid Charging: Disabled

### Evening Configuration (9:15 PM CDT)
- Backup Reserve: 100%
- Operational Mode: Autonomous  
- Energy Exports: Solar Only
- Grid Charging: Enabled

## Monitoring

View logs in AWS CloudWatch:
- `/aws/lambda/netzero-morning-config`
- `/aws/lambda/netzero-evening-config`

## GitHub Actions Workflow

The pipeline triggers on:
- Push to main branch (full deployment)
- Pull requests (plan only)
- Manual workflow dispatch

## API Reference

Uses NetZero Developer API: https://docs.netzero.energy/docs/tesla/API.html