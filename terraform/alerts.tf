# Give IAM time to propagate the deploy user's SNS/SQS/CloudWatch grants before
# any resource that needs them is created. Without this, a fresh apply can fire
# CreateTopic/CreateQueue within ~1s of the policy update and get a 403 because
# the grant hasn't propagated yet (IAM is eventually consistent).
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on      = [aws_iam_user_policy.github_actions_policy]
  create_duration = "30s"

  # Re-wait whenever the policy document changes, so future permission additions
  # get the same propagation grace period.
  triggers = {
    policy = aws_iam_user_policy.github_actions_policy.policy
  }
}

# SNS topic for failure alerts
resource "aws_sns_topic" "alerts" {
  name = "netzero-alerts"

  # Wait for the deploy user's SNS permissions to propagate before creating
  depends_on = [time_sleep.wait_for_iam_propagation]
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

  # Wait for the deploy user's SQS permissions to propagate before creating
  depends_on = [time_sleep.wait_for_iam_propagation]
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

  depends_on = [time_sleep.wait_for_iam_propagation]
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

  depends_on = [time_sleep.wait_for_iam_propagation]
}
