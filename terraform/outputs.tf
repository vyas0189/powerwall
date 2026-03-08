output "morning_lambda_arn" {
  value = aws_lambda_function.morning_config.arn
}

output "evening_lambda_arn" {
  value = aws_lambda_function.evening_config.arn
}

output "morning_schedule_arn" {
  value = aws_scheduler_schedule.morning_schedule.arn
}

output "evening_schedule_arn" {
  value = aws_scheduler_schedule.evening_schedule.arn
}
