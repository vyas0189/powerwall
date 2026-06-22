# SNS topic for failure alerts
resource "aws_sns_topic" "alerts" {
  name = "netzero-alerts"

  # Ensure the deploy user's SNS permissions exist before creating the topic
  depends_on = [aws_iam_user_policy.github_actions_policy]
}

# Email subscription. AWS sends a confirmation email to this address; the
# subscription stays "pending confirmation" until the link in that email is
# clicked. Alerts are only delivered after confirmation.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Dead-letter queue for scheduler events whose Lambda invocations exhaust all
# retries. Lets you inspect/replay runs that failed even after retrying.
resource "aws_sqs_queue" "scheduler_dlq" {
  name                      = "netzero-scheduler-dlq"
  message_retention_seconds = 1209600 # 14 days (max)

  # Ensure the deploy user's SQS permissions exist before creating the queue
  depends_on = [aws_iam_user_policy.github_actions_policy]
}

# Allow EventBridge Scheduler (via the scheduler role) to send dead-letter
# messages to the queue.
resource "aws_sqs_queue_policy" "scheduler_dlq_policy" {
  queue_url = aws_sqs_queue.scheduler_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.scheduler_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_scheduler_schedule.morning_schedule.arn,
              aws_scheduler_schedule.evening_schedule.arn
            ]
          }
        }
      }
    ]
  })
}

# CloudWatch alarm on morning Lambda errors -> SNS email alert
resource "aws_cloudwatch_metric_alarm" "morning_errors" {
  alarm_name          = "netzero-morning-config-errors"
  alarm_description   = "Morning Tesla config Lambda failed (after in-code retries)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.morning_config.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  depends_on = [aws_iam_user_policy.github_actions_policy]
}

# CloudWatch alarm on evening Lambda errors -> SNS email alert
resource "aws_cloudwatch_metric_alarm" "evening_errors" {
  alarm_name          = "netzero-evening-config-errors"
  alarm_description   = "Evening Tesla config Lambda failed (after in-code retries)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.evening_config.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  depends_on = [aws_iam_user_policy.github_actions_policy]
}
