terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  backend "s3" {
    bucket       = "netzero-terraform-state-358870220937"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 state locking (Terraform >= 1.10)
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "netzero-scheduler"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}
