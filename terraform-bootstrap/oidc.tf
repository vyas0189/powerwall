# GitHub Actions OIDC for CI authentication
#
# These resources let the deploy workflow assume a short-lived IAM role via an
# OIDC token instead of long-lived AWS access keys. They live in the bootstrap
# config because creating an IAM identity provider requires permissions the
# least-privilege CI user deliberately does NOT have -- so an admin applies this
# once. It is purely additive: it does not touch the existing CI user, its
# access keys, or the running pipeline.
#
# Apply (admin creds), targeting only these resources so it ignores the
# pre-existing state bucket:
#
#   cd terraform-bootstrap
#   terraform init
#   terraform apply \
#     -target=aws_iam_openid_connect_provider.github \
#     -target=aws_iam_role.github_actions_oidc \
#     -target=aws_iam_role_policy_attachment.oidc_deploy \
#     -target=aws_iam_role_policy.oidc_control_plane

# OIDC identity provider for GitHub Actions.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates the GitHub OIDC endpoint against its own trust store and no
  # longer enforces this thumbprint, but the argument is still required.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Role the deploy workflow assumes. Trust is scoped to this repo's main branch
# so only pushes to main (the deploy trigger) can assume it.
resource "aws_iam_role" "github_actions_oidc" {
  name = "netzero-github-actions-oidc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:vyas0189/powerwall:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# Operational/data-plane permissions: reuse the same customer-managed policy the
# CI user already has (created by the main Terraform config), referenced by ARN.
resource "aws_iam_role_policy_attachment" "oidc_deploy" {
  role       = aws_iam_role.github_actions_oidc.name
  policy_arn = "arn:aws:iam::358870220937:policy/netzero-deploy"
}

# Control-plane permissions: lets the deploy role manage the netzero-* IAM roles
# and the managed policy, plus logs and Terraform state. (The former long-lived
# CI user, netzero-github-actions, was retired, so its user-scoped grants have
# been removed.)
resource "aws_iam_role_policy" "oidc_control_plane" {
  name = "netzero-control-plane"
  role = aws_iam_role.github_actions_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:CreateRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy"
        ]
        Resource = "arn:aws:iam::358870220937:role/netzero-*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyTags",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = "arn:aws:iam::358870220937:policy/netzero-*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:us-east-1:358870220937:log-group:/aws/lambda/netzero-*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        # Covers the state object plus the native S3 lock file
        # (terraform.tfstate.tflock, written when use_lockfile = true) and
        # state backups.
        Resource = "arn:aws:s3:::netzero-terraform-state-358870220937/terraform.tfstate*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::netzero-terraform-state-358870220937"
      }
    ]
  })
}

output "github_actions_oidc_role_arn" {
  description = "ARN of the role the deploy workflow should assume via OIDC."
  value       = aws_iam_role.github_actions_oidc.arn
}
