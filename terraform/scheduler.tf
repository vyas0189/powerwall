# EventBridge Scheduler for morning schedule (6:45 AM CST/CDT - DST handled automatically)
resource "aws_scheduler_schedule" "morning_schedule" {
  name        = "netzero-morning-schedule"
  description = "Trigger morning Tesla configuration at 6:45 AM CST/CDT daily"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(45 6 * * ? *)"
  schedule_expression_timezone = "America/Chicago"

  target {
    arn      = aws_lambda_function.morning_config.arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}

# EventBridge Scheduler for evening schedule (9:15 PM CST/CDT - DST handled automatically)
resource "aws_scheduler_schedule" "evening_schedule" {
  name        = "netzero-evening-schedule"
  description = "Trigger evening Tesla configuration at 9:15 PM CST/CDT daily"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(15 21 * * ? *)"
  schedule_expression_timezone = "America/Chicago"

  target {
    arn      = aws_lambda_function.evening_config.arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}
