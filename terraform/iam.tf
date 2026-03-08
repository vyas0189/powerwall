# IAM policy for GitHub Actions user
# This policy grants permissions needed for Terraform to manage the infrastructure
# Note: This user was created manually and is being imported into Terraform

resource "aws_iam_user_policy" "github_actions_policy" {
  name = "GitHubActionsPolicy"
  user = "netzero-github-actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaFunctionManagement"
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
        Resource = [
          "arn:aws:lambda:us-east-1:358870220937:function:netzero-*",
          "arn:aws:lambda:us-east-1:358870220937:code-signing-config/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-1"
          }
        }
      },
      {
        Sid    = "SchedulerManagement"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:ListTagsForResource",
          "scheduler:TagResource",
          "scheduler:UntagResource"
        ]
        Resource = ["arn:aws:scheduler:us-east-1:358870220937:schedule/default/netzero-*"]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-1"
          }
        }
      },
      {
        Sid    = "IAMRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = ["arn:aws:iam::358870220937:role/netzero-*"]
      },
      {
        Sid    = "IAMRolePolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy"
        ]
        Resource = ["arn:aws:iam::358870220937:role/netzero-*"]
      },
      {
        Sid    = "IAMUserPolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:GetUserPolicy",
          "iam:PutUserPolicy"
        ]
        Resource = ["arn:aws:iam::358870220937:user/netzero-github-actions"]
      },
      {
        Sid    = "CloudWatchLogsManagement"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups"
        ]
        Resource = ["arn:aws:logs:us-east-1:358870220937:log-group:/aws/lambda/netzero-*"]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-1"
          }
        }
      },
      {
        Sid    = "TerraformStateManagement"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["arn:aws:s3:::netzero-terraform-state-358870220937/terraform.tfstate"]
      },
      {
        Sid      = "TerraformStateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::netzero-terraform-state-358870220937"]
        Condition = {
          StringLike = {
            "s3:prefix" = "terraform.tfstate"
          }
        }
      }
    ]
  })
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
  name = "netzero-scheduler-role"

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
      }
    ]
  })
}
