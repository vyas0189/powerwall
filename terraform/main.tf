terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9"
    }
  }

  backend "s3" {
    bucket  = "netzero-terraform-state-358870220937"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "api_key" {
  description = "NetZero API key"
  type        = string
  sensitive   = true
}

variable "site_id" {
  description = "Tesla site ID"
  type        = string
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

# Lambda function for morning configuration
resource "aws_lambda_function" "morning_config" {
  filename         = "morning_config.zip"
  function_name    = "netzero-morning-config"
  role             = aws_iam_role.lambda_role.arn
  handler          = "morning_config.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = base64sha256("${filemd5("${path.module}/../morning_config.py")}-${filemd5("${path.module}/../requirements.txt")}")

  environment {
    variables = {
      API_KEY = var.api_key
      SITE_ID = var.site_id
    }
  }

  depends_on = [null_resource.morning_package]
}

# Lambda function for evening configuration
resource "aws_lambda_function" "evening_config" {
  filename         = "evening_config.zip"
  function_name    = "netzero-evening-config"
  role             = aws_iam_role.lambda_role.arn
  handler          = "evening_config.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = base64sha256("${filemd5("${path.module}/../evening_config.py")}-${filemd5("${path.module}/../requirements.txt")}")

  environment {
    variables = {
      API_KEY = var.api_key
      SITE_ID = var.site_id
    }
  }

  depends_on = [null_resource.evening_package]
}


# Create deployment packages with dependencies
resource "null_resource" "morning_package" {
  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/..
      rm -rf temp_morning
      mkdir -p temp_morning
      cp morning_config.py temp_morning/
      cp requirements.txt temp_morning/
      cd temp_morning
      pip3 install -r requirements.txt -t .
      zip -r ../terraform/morning_config.zip .
      cd ..
      rm -rf temp_morning
    EOT
  }

  triggers = {
    source_code_hash  = filemd5("${path.module}/../morning_config.py")
    requirements_hash = filemd5("${path.module}/../requirements.txt")
  }
}

resource "null_resource" "evening_package" {
  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/..
      rm -rf temp_evening
      mkdir -p temp_evening
      cp evening_config.py temp_evening/
      cp requirements.txt temp_evening/
      cd temp_evening
      pip3 install -r requirements.txt -t .
      zip -r ../terraform/evening_config.zip .
      cd ..
      rm -rf temp_evening
    EOT
  }

  triggers = {
    source_code_hash  = filemd5("${path.module}/../evening_config.py")
    requirements_hash = filemd5("${path.module}/../requirements.txt")
  }
}

# EventBridge rule for morning schedule during CDT (Daylight Saving Time)
# 6:45 AM CDT = 11:45 AM UTC
# Active from 2nd Sunday in March to 1st Sunday in November
resource "aws_cloudwatch_event_rule" "morning_schedule_cdt" {
  name                = "netzero-morning-schedule-cdt"
  description         = "Trigger morning Tesla configuration at 6:45 AM CDT (Daylight Saving Time)"
  schedule_expression = "cron(45 11 ? 3-10 * *)"
  state               = "ENABLED"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "morning_target_cdt" {
  rule      = aws_cloudwatch_event_rule.morning_schedule_cdt.name
  target_id = "MorningConfigTargetCDT"
  arn       = aws_lambda_function.morning_config.arn
}

resource "aws_lambda_permission" "morning_eventbridge_cdt" {
  statement_id  = "AllowExecutionFromEventBridgeCDT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.morning_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_schedule_cdt.arn
}

# EventBridge rule for morning schedule during November (transition month)
# Covers both CDT and CST for November
resource "aws_cloudwatch_event_rule" "morning_schedule_nov" {
  name                = "netzero-morning-schedule-nov"
  description         = "Trigger morning Tesla configuration at 6:45 AM during November transition"
  schedule_expression = "cron(45 11,12 ? 11 * *)"
  state               = "ENABLED"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "morning_target_nov" {
  rule      = aws_cloudwatch_event_rule.morning_schedule_nov.name
  target_id = "MorningConfigTargetNov"
  arn       = aws_lambda_function.morning_config.arn
}

resource "aws_lambda_permission" "morning_eventbridge_nov" {
  statement_id  = "AllowExecutionFromEventBridgeNov"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.morning_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_schedule_nov.arn
}

# EventBridge rule for morning schedule during CST (Standard Time)
# 6:45 AM CST = 12:45 PM UTC
# Active from 1st Sunday in November to 2nd Sunday in March
resource "aws_cloudwatch_event_rule" "morning_schedule_cst" {
  name                = "netzero-morning-schedule-cst"
  description         = "Trigger morning Tesla configuration at 6:45 AM CST (Standard Time)"
  schedule_expression = "cron(45 12 ? 12-2 * *)"
  state               = "ENABLED"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "morning_target_cst" {
  rule      = aws_cloudwatch_event_rule.morning_schedule_cst.name
  target_id = "MorningConfigTargetCST"
  arn       = aws_lambda_function.morning_config.arn
}

resource "aws_lambda_permission" "morning_eventbridge_cst" {
  statement_id  = "AllowExecutionFromEventBridgeCST"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.morning_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_schedule_cst.arn
}

# EventBridge rule for evening schedule during CDT (Daylight Saving Time)
# 9:15 PM CDT = 2:15 AM UTC (next day)
# Active from 2nd Sunday in March to 1st Sunday in November
resource "aws_cloudwatch_event_rule" "evening_schedule_cdt" {
  name                = "netzero-evening-schedule-cdt"
  description         = "Trigger evening Tesla configuration at 9:15 PM CDT (Daylight Saving Time)"
  schedule_expression = "cron(15 2 ? 3-10 * *)"
  state               = "ENABLED"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "evening_target_cdt" {
  rule      = aws_cloudwatch_event_rule.evening_schedule_cdt.name
  target_id = "EveningConfigTargetCDT"
  arn       = aws_lambda_function.evening_config.arn
}

resource "aws_lambda_permission" "evening_eventbridge_cdt" {
  statement_id  = "AllowExecutionFromEventBridgeCDT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.evening_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.evening_schedule_cdt.arn
}

# EventBridge rule for evening schedule during November (transition month)
# Covers both CDT and CST for November
resource "aws_cloudwatch_event_rule" "evening_schedule_nov" {
  name                = "netzero-evening-schedule-nov"
  description         = "Trigger evening Tesla configuration at 9:15 PM during November transition"
  schedule_expression = "cron(15 2,3 ? 11 * *)"
  state               = "ENABLED"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "evening_target_nov" {
  rule      = aws_cloudwatch_event_rule.evening_schedule_nov.name
  target_id = "EveningConfigTargetNov"
  arn       = aws_lambda_function.evening_config.arn
}

resource "aws_lambda_permission" "evening_eventbridge_nov" {
  statement_id  = "AllowExecutionFromEventBridgeNov"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.evening_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.evening_schedule_nov.arn
}

# EventBridge rule for evening schedule during CST (Standard Time)
# 9:15 PM CST = 3:15 AM UTC (next day)
# Active from 1st Sunday in November to 2nd Sunday in March
resource "aws_cloudwatch_event_rule" "evening_schedule_cst" {
  name                = "netzero-evening-schedule-cst"
  description         = "Trigger evening Tesla configuration at 9:15 PM CST (Standard Time)"
  schedule_expression = "cron(15 3 ? 12-2 * *)"
  state               = "ENABLED"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "evening_target_cst" {
  rule      = aws_cloudwatch_event_rule.evening_schedule_cst.name
  target_id = "EveningConfigTargetCST"
  arn       = aws_lambda_function.evening_config.arn
}

resource "aws_lambda_permission" "evening_eventbridge_cst" {
  statement_id  = "AllowExecutionFromEventBridgeCST"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.evening_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.evening_schedule_cst.arn
}

# Outputs
output "morning_lambda_arn" {
  value = aws_lambda_function.morning_config.arn
}

output "evening_lambda_arn" {
  value = aws_lambda_function.evening_config.arn
}
