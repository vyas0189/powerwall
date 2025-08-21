# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | ✅ |

## Reporting a Vulnerability

We take security vulnerabilities seriously and appreciate your efforts to responsibly disclose your findings.

### How to Report

Please report security vulnerabilities by creating a private security advisory through GitHub:

1. Go to the [Security tab](https://github.com/vyas0189/powerwall/security) of this repository
2. Click "Report a vulnerability"
3. Fill out the security advisory form with details about the vulnerability

### What to Include

When reporting a vulnerability, please include:

- A clear description of the vulnerability
- Steps to reproduce the issue
- Potential impact of the vulnerability
- Any suggested fixes or mitigations
- Your contact information (optional)

### Response Timeline

- **Initial Response**: Within 48 hours of report submission
- **Assessment**: Within 5 business days
- **Fix Timeline**: Critical vulnerabilities will be patched within 7 days, others within 30 days
- **Disclosure**: After fix is deployed and users have had time to update

### Security Measures

This project implements several security measures:

- AWS IAM least privilege policies
- GitHub branch protection with required reviews
- Automated security scanning with CodeQL
- Secret scanning with push protection
- Dependabot security updates
- Encrypted environment variables in AWS Lambda

### Scope

This security policy covers:

- The Tesla Powerwall scheduler application code
- AWS infrastructure configuration (Terraform)
- GitHub Actions workflows
- Dependencies and third-party libraries

### Out of Scope

- Issues in third-party services (AWS, Tesla, NetZero API)
- General configuration or usage questions
- Performance issues not related to security

## Security Contact

For urgent security matters, you can also reach out via GitHub issues with the `security` label, though private security advisories are preferred for vulnerability reports.

Thank you for helping keep this project secure!