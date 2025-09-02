resource "aws_cloudwatch_log_metric_filter" "icmp_echo_count" {
  name           = "ICMPPackets"
  log_group_name = aws_cloudwatch_log_group.vpc_flow.name

  pattern = "[version, account, interface, srcaddr, dstaddr, srcport, dstport, protocol=1, packets, bytes, start, end, action, status]"

  metric_transformation {
    name      = "ICMPPackets"
    namespace = "DoSDemo"
    value     = "$packets"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "icmp_flood_alarm" {
  alarm_name          = "ICMPFloodHigh"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.icmp_echo_count.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.icmp_echo_count.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 200

  alarm_actions = [aws_sns_topic.dos_alerts.arn]
}

resource "aws_cloudwatch_log_metric_filter" "tcp_scan_count" {
  name           = "PortScanRejects"
  log_group_name = aws_cloudwatch_log_group.vpc_flow.name

  pattern = "[version, account, interface, srcaddr, dstaddr, srcport, dstport, protocol=6, packets=1, bytes, start, end, action=\"REJECT\", status]"

  metric_transformation {
    name      = "PortScanRejects"
    namespace = "DoSDemo"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "tcp_scan_alarm" {
  alarm_name          = "PortScanHigh"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 60
  statistic           = "Sum"
  threshold           = 50

  metric_name = aws_cloudwatch_log_metric_filter.tcp_scan_count.metric_transformation[0].name
  namespace   = aws_cloudwatch_log_metric_filter.tcp_scan_count.metric_transformation[0].namespace

  alarm_actions = [aws_sns_topic.dos_alerts.arn]
}

resource "aws_cloudwatch_log_metric_filter" "http2_rapid_reset" {
  name           = "HTTP2RapidReset"
  log_group_name = "/nginx/access"

  pattern = "\"PRI * HTTP/2.0\""

  metric_transformation {
    name      = "RapidResetAccess"
    namespace = "DoSDemo"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "rapid_reset_access_alarm" {
  alarm_name          = "RapidResetAccessHigh"
  namespace           = aws_cloudwatch_log_metric_filter.http2_rapid_reset.metric_transformation[0].namespace
  metric_name         = aws_cloudwatch_log_metric_filter.http2_rapid_reset.metric_transformation[0].name
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"

  alarm_actions = [aws_sns_topic.dos_alerts.arn]
}

resource "aws_sns_topic" "dos_alerts" {
  name = "DosAlerts"
}

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "blocker" {
  name               = "auto-block-ip-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy" "blocker_inline" {
  name = "sg-edit"
  role = aws_iam_role.blocker.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeSecurityGroups", 
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "block_ip" {
  filename         = "lambda_block.zip"
  source_code_hash = filebase64sha256("lambda_block.zip")
  function_name    = "AutoBlockIP"
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.blocker.arn
  timeout          = 300

  environment {
    variables = {
      TARGET_SG = aws_security_group.app_sg.id
      BLOCK_SEC = "100"  
    }
  }
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSTrigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.block_ip.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.dos_alerts.arn
}

resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.dos_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.block_ip.arn
}