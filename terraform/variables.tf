variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "site_id" {
  description = "Tesla site ID"
  type        = string
}

variable "api_key_param_name" {
  description = "Name of the SSM Parameter Store SecureString holding the NetZero API key. The parameter is created out-of-band (not by Terraform) so the secret value never enters Terraform state."
  type        = string
  default     = "/netzero/api_key"
}

variable "alert_email" {
  description = "Email address that receives failure alerts for the Lambda jobs"
  type        = string
  default     = "vyas0189@gmail.com"
}
