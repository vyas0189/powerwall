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
