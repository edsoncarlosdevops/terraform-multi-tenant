#  VPC Flow Logs (Auditoria/Segurança) 
# Apenas em produção para reduzir custos

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.environment == "prod" ? 1 : 0

  name              = "${local.name_prefix}-vpc-flow-logs"
  retention_in_days = 90

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-flow-logs"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_flow_log" "this" {
  count = var.environment == "prod" ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpc-flow-log"
    Tenant      = var.tenant
    Environment = var.environment
  })
}

#  IAM Role para Flow Logs 
resource "aws_iam_role" "flow_logs" {
  count = var.environment == "prod" ? 1 : 0

  name = "${local.name_prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Tenant      = var.tenant
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.environment == "prod" ? 1 : 0

  name = "${local.name_prefix}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
