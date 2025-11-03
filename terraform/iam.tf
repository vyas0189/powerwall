# IAM policy for GitHub Actions user
# This policy grants permissions needed for Terraform to manage the infrastructure

resource "aws_iam_user_policy" "github_actions_policy" {
  name = "netzero-github-actions-policy"
  user = "netzero-github-actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaManagement"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:ListVersionsByFunction",
          "lambda:PublishVersion",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy"
        ]
        Resource = [
          "arn:aws:lambda:*:*:function:netzero-*"
        ]
      },
      {
        Sid    = "EventBridgeManagement"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DeleteRule",
          "events:DescribeRule",
          "events:EnableRule",
          "events:DisableRule",
          "events:ListRules",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:ListTargetsByRule"
        ]
        Resource = [
          "arn:aws:events:*:*:rule/netzero-*"
        ]
      },
      {
        Sid    = "IAMManagement"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/netzero-*"
        ]
      },
      {
        Sid    = "TerraformStateManagement"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::netzero-terraform-state-*",
          "arn:aws:s3:::netzero-terraform-state-*/*"
        ]
      },
      {
        Sid    = "DynamoDBStateManagement"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:dynamodb:*:*:table/netzero-terraform-lock"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups",
          "logs:DeleteLogGroup"
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/lambda/netzero-*"
        ]
      }
    ]
  })
}
