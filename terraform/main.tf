# --------------------------------------- #
# Define IAM Role for Lambda Function
# --------------------------------------- #
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  tags = local.default_tags
}

# Attach IAM policy to the Lambda role for Secrets Manager access
resource "aws_iam_policy" "lambda_secrets_policy" {
  name = "lambda_secrets_policy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
  tags = local.default_tags
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_attachment" {
  policy_arn = aws_iam_policy.lambda_secrets_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# IAM Policy to access RDS
resource "aws_iam_policy" "lambda_rds_policy" {
  name = "lambda_rds_policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["rds-db:connect"],
        Effect   = "Allow",
        Resource = "arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:*/${var.db_name}"
      }
    ]
  })
  tags = local.default_tags
}

# Attach IAM policy to the Lambda role for RDS access
resource "aws_iam_role_policy_attachment" "lambda_rds_attachment" {
  policy_arn = aws_iam_policy.lambda_rds_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

resource "aws_iam_policy" "lambda_network_access_policy" {
  name = "lambda_ec2_network_policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs",
                "ec2:DescribeNetworkInterfaces",
                "ec2:CreateNetworkInterface",
                "ec2:DeleteNetworkInterface",
                "ec2:DescribeInstances",
                "ec2:AttachNetworkInterface"
            ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
  tags = local.default_tags
}

# Attach IAM policy to the Lambda role for S3 and RDS access
resource "aws_iam_role_policy_attachment" "lambda_network_access_attachment" {
  policy_arn = aws_iam_policy.lambda_network_access_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# IAM Policy Get Code Signing Config
resource "aws_iam_policy" "GetCodeSigningConfig_policy" {
  name = "lambda_GetCodeSigningConfig_policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["lambda:GetCodeSigningConfig"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
  tags = local.default_tags
}

# Attach IAM policy to the Lambda role for RDS access
resource "aws_iam_role_policy_attachment" "lambda_codesigning_attachment" {
  policy_arn = aws_iam_policy.GetCodeSigningConfig_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# --------------------------------------- #
# Secret Manager
# --------------------------------------- #
resource "aws_secretsmanager_secret" "LambdaSecret" {
  name                           = "${var.secret_manager_name}-${var.environment}"
  description                    = "Stores secrets to access RDS Postgres DB"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0

  tags = local.default_tags
}

resource "aws_secretsmanager_secret_version" "ADCredentials" {
  secret_id = aws_secretsmanager_secret.LambdaSecret.id
  secret_string = jsonencode(tomap({
    "username"   = var.db_user
    "password" = var.db_password
  }))
}

# --------------------------------------- #
# Lambda function
# --------------------------------------- #
resource "aws_lambda_function" "postgres_lambda_function" {
  function_name    = "lambda-postgres-datarotation-${var.environment}"
  filename         = data.archive_file.python_lambda_package.output_path
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 120
  memory_size      = 1024

  environment {
    variables = {
      secret_name  = aws_secretsmanager_secret.LambdaSecret.name
      region_name  = var.region
      rds_hostname = var.rds_hostname
      db_name      = var.db_name
    }
  }

  # VPC configuration
  vpc_config {
    subnet_ids         = [for subnet in data.aws_subnets.internal.ids : subnet]
    security_group_ids = [aws_security_group.lambda_postgres_security_group.id]
  }

  tags = local.default_tags
}

# Create a security group for the Lambda function
resource "aws_security_group" "lambda_postgres_security_group" {
  name_prefix = "Lambda_RDS_SecurityGroup-${var.environment}"
  vpc_id      = data.aws_vpc.vpc01.id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    prefix_list_ids = [
      data.aws_ec2_managed_prefix_list.AWSInternal.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.default_tags
}

# --------------------------------------- #
# Cloud Watch Event brigde
# --------------------------------------- #
resource "aws_cloudwatch_event_rule" "schedule" {
    name = "Lambda_schedule-${var.environment}"
    description = "Schedule for Lambda Function"
    schedule_expression = var.schedule
    tags = local.default_tags
}

resource "aws_cloudwatch_event_target" "schedule_lambda" {
    rule = aws_cloudwatch_event_rule.schedule.name
    target_id = "processing_lambda"
    arn = aws_lambda_function.postgres_lambda_function.arn
}

resource "aws_lambda_permission" "allow_events_bridge_to_run_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.postgres_lambda_function.function_name
    principal = "events.amazonaws.com"
}
