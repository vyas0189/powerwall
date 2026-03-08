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
