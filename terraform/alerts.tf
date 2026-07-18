# Give IAM time to propagate changes to the deploy role's operational grants
# before any resource that needs them is created. Those permissions come from the
# customer-managed policy (aws_iam_policy.deploy), attached to the OIDC deploy
# role in terraform-bootstrap. Without this, a fresh apply can fire
# CreateTopic/CreateQueue within ~1s of a grant change and get a 403 (IAM is
# eventually consistent).
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on      = [aws_iam_policy.deploy]
  create_duration = "30s"

  # Re-wait whenever the managed policy document changes, so future permission
  # additions get the same propagation grace period.
  triggers = {
    policy = aws_iam_policy.deploy.policy
  }
}

# SNS topic for failure alerts
resource "aws_sns_topic" "alerts" {
  name = "netzero-alerts"

  # NOTE: Do NOT set kms_master_key_id = "alias/aws/sns" here. The AWS-managed
  # SNS key has a fixed key policy that does not grant the CloudWatch service
  # principal (cloudwatch.amazonaws.com) kms:GenerateDataKey*/kms:Decrypt, so
  # CloudWatch alarms silently fail to publish ("Failed to execute action") and
  # no alert email is sent. This topic carries only alarm metadata (no secrets),
  # so it is intentionally left unencrypted. If encryption at rest is required,
  # use a customer-managed KMS key whose policy grants cloudwatch.amazonaws.com
  # (and events.amazonaws.com) those actions.

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

  # Encrypt messages at rest with SSE-SQS (SQS-managed keys; no KMS perms/cost).
  sqs_managed_sse_enabled = true

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

# Alarm when any scheduler event lands in the dead-letter queue (i.e. a run
# failed even after in-code and scheduler retries) so failures aren't silent.
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "netzero-scheduler-dlq-messages"
  alarm_description   = "A scheduled Tesla config run exhausted all retries and was dead-lettered"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.scheduler_dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  depends_on = [time_sleep.wait_for_iam_propagation]
}
