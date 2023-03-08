# Lambda-Postgres-DataRotation

## Project generates Lambda function to rotate old data into RDS Postgres database

## Prerequisites

- AWS
- Terraform
- Python
- Postgres TSQ

## Python libraries used
- `Psycopg 2`

Psycopg 2 is mostly implemented in C as a libpq wrapper, resulting in being both efficient and secure. It features client-side and server-side cursors, asynchronous communication and notifications, COPY support.

Documentation: https://www.psycopg.org/docs/

## Function Description

Lambda function rotates old records from operational tables into archive tables on shedule basis.

Lambda is writtem in Python with external library `Psycopg2`. 

Function connects to the Database using the secrets obtained from AWS Secrets manager. After function executes queries for the tables described in `config.json` file. Requests old records as configured in config.json file and moves them into <TABLE_NAME>_ARCHIVE database table.

All function execution steps are logged with python logger and saves into CloudWatch function metrics

## `Config.json` configuration gile.

You can set as many tables to rotate as required.

Config parameters description:

- `TABLE_NAME` - Name of the database table to rotate
- `LIMIT` - Number of rows that needs to be batched at a time
- `WHERE_KEYS` - The basis on which you want to archive the table as per the use case
- `KEY` - Primary key used for delete query

## Variables

Environmental variables are placed into `gitlab/.terraform-ci.yml` file
Set the variables in accordance to the evnironments:

 - `account_id` - AWS account ID to run the Terraform
 - `secret_manager_name` - Name of the AWS secrets manager to store DB credentials in
 - `rds_hostname` - RDS Database endpoint name
 - `db_name` - RDS database name
 - `schedule` - cron expression for Lambda scheduling
 - `db_user` - Database username, obtains from GitLab variables
 - `db_password` - Database password, obtains from GitLab variables

Cron schedule helper: https://crontab.guru/

 ## List of Terraform resources:

 - IAM Role for Lambda function
 - IAM Polycy for Lambda to obtain secrets from Secrets manager
 - IAM Policy for Lambda to obtain eccess to RDS DB
 - Secrets manager resource, stores DB access secret
 - Lambda function
 - Security group for Lambda
 - EventBridge to schedule Lambda function execution
