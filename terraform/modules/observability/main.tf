variable "name" {}
variable "region" {}
variable "alert_email" {}
variable "alb_arn_suffix" {}
variable "api_tg_suffix" {}
variable "cluster_name" {}
variable "db_identifier" {}
variable "redis_id" {}

resource "aws_sns_topic" "alerts" { name = "${var.name}-alerts" }
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Every alarm answers "is a user hurting, or about to be?" rather than just "is a number high?"
locals {
  alb_dim   = { LoadBalancer = var.alb_arn_suffix }
  api_dim   = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.api_tg_suffix }
  redis_dim = { CacheClusterId = "${var.redis_id}-001" }
  alarms = {
    alb-5xx          = { ns = "AWS/ApplicationELB", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", op = "GreaterThanThreshold", threshold = 10, missing = "notBreaching", dims = local.alb_dim, desc = "API is returning server errors" }
    api-unhealthy    = { ns = "AWS/ApplicationELB", metric = "UnHealthyHostCount", stat = "Maximum", op = "GreaterThanThreshold", threshold = 0, missing = "notBreaching", dims = local.api_dim, desc = "An API task is failing health checks" }
    api-slow-p95     = { ns = "AWS/ApplicationELB", metric = "TargetResponseTime", stat = "p95", op = "GreaterThanThreshold", threshold = 1, missing = "notBreaching", dims = local.api_dim, desc = "95% of API responses take over 1s" }
    api-tasks-down   = { ns = "ECS/ContainerInsights", metric = "RunningTaskCount", stat = "Minimum", op = "LessThanThreshold", threshold = 1, missing = "breaching", dims = { ClusterName = var.cluster_name, ServiceName = "api" }, desc = "No API tasks are running" }
    rds-cpu          = { ns = "AWS/RDS", metric = "CPUUtilization", stat = "Average", op = "GreaterThanThreshold", threshold = 80, missing = "notBreaching", dims = { DBInstanceIdentifier = var.db_identifier }, desc = "Database CPU above 80%" }
    rds-low-storage  = { ns = "AWS/RDS", metric = "FreeStorageSpace", stat = "Minimum", op = "LessThanThreshold", threshold = 2000000000, missing = "notBreaching", dims = { DBInstanceIdentifier = var.db_identifier }, desc = "Database has under 2 GB free" }
    redis-cpu        = { ns = "AWS/ElastiCache", metric = "EngineCPUUtilization", stat = "Average", op = "GreaterThanThreshold", threshold = 80, missing = "notBreaching", dims = local.redis_dim, desc = "Redis CPU above 80%" }
    redis-memory     = { ns = "AWS/ElastiCache", metric = "DatabaseMemoryUsagePercentage", stat = "Maximum", op = "GreaterThanThreshold", threshold = 80, missing = "notBreaching", dims = local.redis_dim, desc = "Redis memory above 80%" }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.desc
  namespace           = each.value.ns
  metric_name         = each.value.metric
  dimensions          = each.value.dims
  statistic           = startswith(each.value.stat, "p") ? null : each.value.stat
  extended_statistic  = startswith(each.value.stat, "p") ? each.value.stat : null
  comparison_operator = each.value.op
  threshold           = each.value.threshold
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2 # 2 bad minutes out of 3, so one blip does not page anyone
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = { title = "Traffic and errors", region = var.region, period = 60, stat = "Sum", metrics = [
      ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
      [".", "HTTPCode_Target_5XX_Count", ".", "."]] } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = { title = "API latency p95 (seconds)", region = var.region, period = 60, stat = "p95", metrics = [
      ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.api_tg_suffix]] } },
    { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = { title = "API CPU and memory (%)", region = var.region, period = 60, stat = "Average", metrics = [
      ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", "api"],
      [".", "MemoryUtilization", ".", ".", ".", "."]] } },
    { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = { title = "API running tasks", region = var.region, period = 60, stat = "Average", metrics = [
      ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", "api"]] } },
    { type = "metric", x = 0, y = 12, width = 12, height = 6, properties = { title = "Postgres CPU (%) and connections", region = var.region, period = 60, stat = "Average", metrics = [
      ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier],
      [".", "DatabaseConnections", ".", "."]] } },
    { type = "metric", x = 12, y = 12, width = 12, height = 6, properties = { title = "Redis CPU and memory (%)", region = var.region, period = 60, stat = "Average", metrics = [
      ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", "${var.redis_id}-001"],
      [".", "DatabaseMemoryUsagePercentage", ".", "."]] } },
  ] })
}

output "dashboard_url" { value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.name}" }
