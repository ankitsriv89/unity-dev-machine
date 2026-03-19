# --- SNS Topic for auto-stop/terminate alerts ---

resource "aws_sns_topic" "auto_stop_alerts" {
  name = "${var.project_name}-auto-stop-alerts"
  tags = { Project = var.project_name }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.auto_stop_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "sms" {
  topic_arn = aws_sns_topic.auto_stop_alerts.arn
  protocol  = "sms"
  endpoint  = var.alert_phone
}

# --- SSM Parameters ---

resource "aws_ssm_parameter" "keep_alive_pin" {
  name        = "/${var.project_name}/keep-alive-pin"
  description = "PIN for keep-alive command on dev machine"
  type        = "SecureString"
  value       = var.keep_alive_pin

  tags = { Project = var.project_name }
}

resource "aws_ssm_parameter" "sns_topic_arn" {
  name        = "/${var.project_name}/sns-topic-arn"
  description = "SNS topic ARN for auto-stop alerts (used by idle-shutdown.ps1)"
  type        = "String"
  value       = aws_sns_topic.auto_stop_alerts.arn

  tags = { Project = var.project_name }
}

# --- Lambda IAM Role ---

resource "aws_iam_role" "auto_stop_lambda" {
  name = "${var.project_name}-auto-stop-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "auto_stop_lambda" {
  name = "auto-stop-policy"
  role = aws_iam_role.auto_stop_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances"]
        Resource = "arn:aws:ec2:${var.region}:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project_name
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.auto_stop_alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:*:*"
      }
    ]
  })
}

# --- Lambda Function ---

data "archive_file" "auto_terminate" {
  type        = "zip"
  source_file = "${path.module}/../lambda/auto_terminate.py"
  output_path = "${path.module}/../lambda/auto_terminate.zip"
}

resource "aws_lambda_function" "auto_terminate" {
  filename         = data.archive_file.auto_terminate.output_path
  function_name    = "${var.project_name}-auto-terminate"
  role             = aws_iam_role.auto_stop_lambda.arn
  handler          = "auto_terminate.handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = data.archive_file.auto_terminate.output_base64sha256

  environment {
    variables = {
      REGION            = var.region
      PROJECT_TAG       = var.project_name
      INSTANCE_NAME     = local.instance_name
      MAX_RUNTIME_HOURS = tostring(var.max_runtime_hours)
      SNS_TOPIC_ARN     = aws_sns_topic.auto_stop_alerts.arn
    }
  }

  tags = { Project = var.project_name }
}

# --- EventBridge Rule (every 15 minutes) ---

resource "aws_cloudwatch_event_rule" "auto_terminate_check" {
  name                = "${var.project_name}-auto-terminate-check"
  description         = "Check dev instance runtime every 15 min"
  schedule_expression = "rate(15 minutes)"
  tags                = { Project = var.project_name }
}

resource "aws_cloudwatch_event_target" "auto_terminate_lambda" {
  rule      = aws_cloudwatch_event_rule.auto_terminate_check.name
  target_id = "auto-terminate-lambda"
  arn       = aws_lambda_function.auto_terminate.arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_terminate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_terminate_check.arn
}
