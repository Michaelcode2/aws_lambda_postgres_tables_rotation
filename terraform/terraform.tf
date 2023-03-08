terraform {
  required_version = ">= 1.1"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}

# Configure AWS provider
provider "aws" {
  region = "us-east-1"
}
