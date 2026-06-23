# Inline policy for the GitHub Actions deploy user — CONTROL PLANE only.
#
# The operational/data-plane permissions (Lambda, Scheduler, SNS, SQS,
# CloudWatch, Logs) live in the customer-managed policy below, which has a
# 6144-byte limit and so can spell out explicit, least-privilege actions
# instead of the service wildcards an inline policy was forced to use (the
# aggregate inline-policy budget for a user is only 2048 bytes).
#
# This inline policy intentionally retains the permissions needed to manage and
# attach that managed policy, plus self-policy management, so the deploy user
# can always recover from a half-applied change (it can never lock itself out).
resource "aws_iam_user_policy" "github_actions_policy" {
  name = "GitHubActionsPolicy"
  user = "netzero-github-actions"

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
        Effect   = "Allow"
        Action   = ["iam:GetUserPolicy", "iam:PutUserPolicy", "iam:ListAttachedUserPolicies"]
        Resource = "arn:aws:iam::358870220937:user/netzero-github-actions"
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
        # Limit attach/detach to netzero-* managed policies so the deploy user
        # cannot escalate by attaching, e.g., AdministratorAccess to itself.
        Effect   = "Allow"
        Action   = ["iam:AttachUserPolicy", "iam:DetachUserPolicy"]
        Resource = "arn:aws:iam::358870220937:user/netzero-github-actions"
        Condition = {
          ArnLike = {
            "iam:PolicyARN" = "arn:aws:iam::358870220937:policy/netzero-*"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:us-east-1:358870220937:log-group:/aws/lambda/netzero-*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::netzero-terraform-state-358870220937/terraform.tfstate"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::netzero-terraform-state-358870220937"
      }
    ]
  })
}

# Customer-managed policy: the operational/data-plane permissions, explicit and
# scoped to netzero-* resources. 6144-byte limit leaves room to avoid wildcards.
resource "aws_iam_policy" "deploy" {
  name        = "netzero-deploy"
  description = "Operational deploy permissions for netzero infrastructure (Lambda, Scheduler, SNS, SQS, CloudWatch, Logs)."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:GetPolicy"
        ]
        Resource = "arn:aws:lambda:us-east-1:358870220937:function:netzero-*"
      },
      {
        Effect   = "Allow"
        Action   = ["scheduler:CreateSchedule", "scheduler:DeleteSchedule", "scheduler:GetSchedule", "scheduler:UpdateSchedule"]
        Resource = "arn:aws:scheduler:us-east-1:358870220937:schedule/default/netzero-*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:GetSubscriptionAttributes",
          "sns:ListTagsForResource",
          "sns:TagResource",
          "sns:UntagResource"
        ]
        Resource = "arn:aws:sns:us-east-1:358870220937:netzero-*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueueTags",
          "sqs:TagQueue",
          "sqs:UntagQueue"
        ]
        Resource = "arn:aws:sqs:us-east-1:358870220937:netzero-*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource"
        ]
        Resource = "arn:aws:cloudwatch:us-east-1:358870220937:alarm:netzero-*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:us-east-1:358870220937:log-group:/aws/lambda/netzero-*"
      }
    ]
  })
}

# Wait for the inline policy's control-plane grants (CreatePolicy /
# AttachUserPolicy) to propagate before creating/attaching the managed policy.
resource "time_sleep" "wait_for_iam_control_plane" {
  depends_on      = [aws_iam_user_policy.github_actions_policy]
  create_duration = "30s"

  triggers = {
    policy = aws_iam_user_policy.github_actions_policy.policy
  }
}

resource "aws_iam_user_policy_attachment" "deploy" {
  user       = "netzero-github-actions"
  policy_arn = aws_iam_policy.deploy.arn

  depends_on = [time_sleep.wait_for_iam_control_plane]
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "netzero-lambda-role"

  lifecycle {
    ignore_changes = [name]
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# IAM role for EventBridge Scheduler to invoke Lambda
resource "aws_iam_role" "scheduler_role" {
  name       = "netzero-scheduler-role"
  depends_on = [aws_iam_user_policy.github_actions_policy]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  name = "netzero-scheduler-invoke-lambda"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.morning_config.arn,
          aws_lambda_function.evening_config.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.scheduler_dlq.arn
      }
    ]
  })
}
