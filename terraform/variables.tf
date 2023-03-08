variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "secret_manager_name" {
  description = "Name of the AWS Secret"
  type        = string
}

variable "rds_hostname" {
  description = "Name of the RDS Database"
  type        = string
}

variable "db_name" {
  description = "Postgres database name"
  type        = string
}

variable "db_user" {
  description = "Postgres database username"
  type        = string
}

variable "db_password" {
  description = "Postgres database user password"
  type        = string
}

variable "schedule" {
  description = "Postgres database user password"
  type        = string
}

locals {
  default_tags = {
    ManagedBy = "TERRAFORM",
    Env       = var.environment,
    APPID     = "APP01"
  }
}

# variable "environment" {
#   type        = string
# }
