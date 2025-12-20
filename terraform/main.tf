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

# EventBridge rule for morning schedule (6:45 AM CDT = 11:45 AM UTC)
resource "aws_cloudwatch_event_rule" "morning_schedule" {
  name                = "netzero-morning-schedule"
  description         = "Trigger morning Tesla configuration at 6:45 AM CDT daily"
  schedule_expression = "cron(45 12 * * ? *)"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "morning_target" {
  rule      = aws_cloudwatch_event_rule.morning_schedule.name
  target_id = "MorningConfigTarget"
  arn       = aws_lambda_function.morning_config.arn
}

resource "aws_lambda_permission" "morning_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.morning_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_schedule.arn
}

# EventBridge rule for evening schedule (9:15 PM CDT = 2:15 AM UTC next day)
resource "aws_cloudwatch_event_rule" "evening_schedule" {
  name                = "netzero-evening-schedule"
  description         = "Trigger evening Tesla configuration at 9:15 PM CDT daily"
  schedule_expression = "cron(15 3 * * ? *)"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_cloudwatch_event_target" "evening_target" {
  rule      = aws_cloudwatch_event_rule.evening_schedule.name
  target_id = "EveningConfigTarget"
  arn       = aws_lambda_function.evening_config.arn
}

resource "aws_lambda_permission" "evening_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.evening_config.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.evening_schedule.arn
}

# Outputs
output "morning_lambda_arn" {
  value = aws_lambda_function.morning_config.arn
}

output "evening_lambda_arn" {
  value = aws_lambda_function.evening_config.arn
}
