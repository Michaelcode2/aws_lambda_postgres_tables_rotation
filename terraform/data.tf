data "aws_vpc" "vpc01" {
  filter {
    name   = "tag:Name"
    values = ["vpc_*-vpc-01"]
  }
}

data "aws_subnets" "internal" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc01.id]
  }
  tags = {
    Designation = "internal"
  }
}

data "aws_ec2_managed_prefix_list" "AWSInternal" {
  name = "#TODO: XXXXXXXX"
}

data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda-function/"
  output_path = "${path.module}/lambda-postgres-function.zip"
}
