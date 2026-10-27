
# What it creates (resources in brackets exist only for that scenario):
#   - SNS topic "Ops-Alerts" + e-mail subscription        (all scenarios)
#   - Web EC2: CPU > threshold, status check failed       (all scenarios)
#   - [DB EC2: CPU > threshold, status check failed]      (scenario 3)
#   - [RDS: CPU > threshold, free storage low]            (scenario 4)
#   - [Application HTTP 503 alarm, via nginx access logs] (optional, see below)
#
# Notes
#   - SNS sends a confirmation e-mail once: click "Confirm subscription".
#   - Each alarm sends one mail when it changes state (ALARM, and OK when it
#     recovers). A new alarm also sends an "OK" mail after its first evaluation.
#   - The topic is not encrypted with a KMS key on purpose: CloudWatch alarms
#     cannot publish to a topic encrypted with the AWS managed key (alias/aws/sns).
#   - Standard-resolution alarms cost about $0.10 per alarm per month.

variable "enable_monitoring" {
  description = "Create the SNS topic and CloudWatch alarms. Off by default so the measured baseline (21 resources for scenario 1) does not change."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "E-mail address subscribed to the Ops-Alerts SNS topic (confirm the subscription once from the AWS e-mail)."
  type        = string
  default     = "tranhaidang.devops@gmail.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid e-mail address."
  }
}

variable "cpu_alarm_threshold" {
  description = "Average CPU utilization (%) over 5 minutes that triggers the CPU alarms."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be between 1 and 100."
  }
}

variable "enable_http_503_alarm" {
  description = "Also create the application HTTP 503 alarm. Requires the nginx container to ship its access log to CloudWatch Logs (docker awslogs driver, see the comment above the log group)."
  type        = bool
  default     = false
}

variable "web_log_group_name" {
  description = "CloudWatch Logs group that receives the nginx access log (used only when enable_http_503_alarm = true)."
  type        = string
  default     = "/cloudevo/web/nginx"
}

locals {
  monitoring_on  = var.enable_monitoring
  http_503_on    = var.enable_monitoring && var.enable_http_503_alarm
  alarm_prefix   = "${var.project_name}-case${var.scenario_case}"
  alarm_topic    = local.monitoring_on ? aws_sns_topic.ops_alerts[0].arn : null
  rds_min_free_b = 2 * 1024 * 1024 * 1024 # alarm when less than 2 GiB of the 20 GiB volume is free
}

# --- Notification channel -----------------------------------------------------

resource "aws_sns_topic" "ops_alerts" {
  count = local.monitoring_on ? 1 : 0
  name  = "Ops-Alerts"

  tags = {
    Name = "${var.project_name}-ops-alerts"
  }
}

resource "aws_sns_topic_subscription" "ops_email" {
  count     = local.monitoring_on ? 1 : 0
  topic_arn = aws_sns_topic.ops_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Web EC2 (all scenarios) ----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "web_cpu_high" {
  count               = local.monitoring_on ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-web-cpu-high"
  alarm_description   = "Web EC2 average CPU above ${var.cpu_alarm_threshold}% for 5 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.web_ec2.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]
}

resource "aws_cloudwatch_metric_alarm" "web_status_check_failed" {
  count               = local.monitoring_on ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-web-status-check-failed"
  alarm_description   = "Web EC2 failed an instance or system status check for 2 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.web_ec2.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]
}

# --- Database EC2 (scenario 3 only) ---------------------------------------------

resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  count               = local.monitoring_on && var.scenario_case == 3 ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-db-cpu-high"
  alarm_description   = "Database EC2 average CPU above ${var.cpu_alarm_threshold}% for 5 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.db_ec2[0].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]
}

resource "aws_cloudwatch_metric_alarm" "db_status_check_failed" {
  count               = local.monitoring_on && var.scenario_case == 3 ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-db-status-check-failed"
  alarm_description   = "Database EC2 failed an instance or system status check for 2 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.db_ec2[0].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]
}

# --- Amazon RDS (scenario 4 only) -----------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count               = local.monitoring_on && var.scenario_case == 4 ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-rds-cpu-high"
  alarm_description   = "RDS average CPU above ${var.cpu_alarm_threshold}% for 5 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.rds_postgres[0].identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  count               = local.monitoring_on && var.scenario_case == 4 ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-rds-free-storage-low"
  alarm_description   = "RDS free storage below 2 GiB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.rds_postgres[0].identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = local.rds_min_free_b
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]
}

# --- Application HTTP 503 (optional) --------------------------------------------
# EC2 does not publish HTTP status codes, so this alarm counts "503" lines in the
# nginx access log. Before enabling it, ship the nginx container log to the log
# group below by adding this to the nginx service in docker-compose / user data:
#
#   logging:
#     driver: awslogs
#     options:
#       awslogs-region: ap-southeast-1
#       awslogs-group: /cloudevo/web/nginx
#       awslogs-stream: nginx-access
#
# The default nginx log format ("combined") has 9 space-delimited fields, which is
# what the metric filter below expects. Check it in the console with "Test pattern".

resource "aws_cloudwatch_log_group" "web_nginx" {
  count             = local.http_503_on ? 1 : 0
  name              = var.web_log_group_name
  retention_in_days = 7
}

resource "aws_iam_role_policy" "web_cloudwatch_logs" {
  count = local.http_503_on ? 1 : 0
  name  = "${var.project_name}-cloudwatch-logs-write"
  role  = aws_iam_role.ec2_s3_backup_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteNginxAccessLog"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.web_nginx[0].arn}:*"
    }]
  })
}

resource "aws_cloudwatch_log_metric_filter" "http_503" {
  count          = local.http_503_on ? 1 : 0
  name           = "${local.alarm_prefix}-http-503"
  log_group_name = aws_cloudwatch_log_group.web_nginx[0].name
  pattern        = "[ip, id, user, timestamp, request, status_code=503, size, referer, agent]"

  metric_transformation {
    name          = "Http503Count"
    namespace     = "CloudEvo/Web"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "web_http_503" {
  count               = local.http_503_on ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-web-http-503"
  alarm_description   = "The web tier returned HTTP 503 at least once in 1 minute"
  namespace           = "CloudEvo/Web"
  metric_name         = "Http503Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alarm_topic]
  ok_actions          = [local.alarm_topic]

  depends_on = [aws_cloudwatch_log_metric_filter.http_503]
}

# --- Outputs --------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the Ops-Alerts SNS topic (null when enable_monitoring = false)"
  value       = one(aws_sns_topic.ops_alerts[*].arn)
}

output "monitoring_alarms" {
  description = "Names of the CloudWatch alarms created for the active scenario"
  value = concat(
    aws_cloudwatch_metric_alarm.web_cpu_high[*].alarm_name,
    aws_cloudwatch_metric_alarm.web_status_check_failed[*].alarm_name,
    aws_cloudwatch_metric_alarm.db_cpu_high[*].alarm_name,
    aws_cloudwatch_metric_alarm.db_status_check_failed[*].alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu_high[*].alarm_name,
    aws_cloudwatch_metric_alarm.rds_free_storage_low[*].alarm_name,
    aws_cloudwatch_metric_alarm.web_http_503[*].alarm_name,
  )
}
