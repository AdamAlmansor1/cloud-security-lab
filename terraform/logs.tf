resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/vpc/${var.project}-flow"
  retention_in_days = 7
}

data "aws_iam_policy_document" "vpc_flow" {
  statement {
    sid       = "AllowVPCFlowLogs"
    effect    = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions   = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow" {
  name               = "${var.project}-vpc-flow-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow.json
}

resource "aws_iam_role_policy" "vpc_flow" {
  name = "${var.project}-vpc-flow-policy"
  role = aws_iam_role.vpc_flow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc_flow" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn         = aws_iam_role.vpc_flow.arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id

  max_aggregation_interval = 60

  tags = {
    Project = var.project
  }
}
