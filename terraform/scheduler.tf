# EventBridge Scheduler for morning schedule (8:55 AM CST/CDT - DST handled automatically).
# Fires just before 9:00 AM, when the "Twelve Hour Power 24" free period ends and grid
# power jumps to ~27.7c/kWh, so grid charging is already off by the time the meter starts
# charging for it.
resource "aws_scheduler_schedule" "morning_schedule" {
  name        = "netzero-morning-schedule"
  description = "Trigger morning Tesla configuration at 8:55 AM CST/CDT daily (just before the 9 AM free-period end)"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(55 8 * * ? *)"
  schedule_expression_timezone = "America/Chicago"

  target {
    arn      = aws_lambda_function.morning_config.arn
    role_arn = aws_iam_role.scheduler_role.arn

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }
  }
}

# EventBridge Scheduler for evening schedule (9:05 PM CST/CDT - DST handled automatically).
# Fires just after 9:00 PM, when the free period begins, so the Powerwall never grid-charges
# while power is still billable.
resource "aws_scheduler_schedule" "evening_schedule" {
  name        = "netzero-evening-schedule"
  description = "Trigger evening Tesla configuration at 9:05 PM CST/CDT daily (just after the 9 PM free-period start)"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(5 21 * * ? *)"
  schedule_expression_timezone = "America/Chicago"

  target {
    arn      = aws_lambda_function.evening_config.arn
    role_arn = aws_iam_role.scheduler_role.arn

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }
  }
}
