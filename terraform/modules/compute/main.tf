variable "name" {}
variable "region" {}
variable "vpc_id" {}
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "alb_sg_id" {}
variable "api_sg_id" {}
variable "web_sg_id" {}
variable "sim_sg_id" {}
variable "db_host" {}
variable "db_secret_arn" {}
variable "redis_host" {}
variable "api_count" { default = 2 }
variable "simulator_count" { default = 1 }
variable "image_tag" { default = "bootstrap" } # placeholder only; the deploy pipeline sets real SHAs
variable "api_max" { default = 6 }

locals { apps = ["api", "web", "simulator"] }

resource "aws_ecr_repository" "repo" {
  for_each     = toset(local.apps)
  name         = "${var.name}/${each.key}"
  force_delete = true
  image_tag_mutability = "IMMUTABLE" # a tag can never be overwritten: SHA = exactly one build
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_cloudwatch_log_group" "logs" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

# Execution role: lets ECS pull images, write logs and read the DB secret on our behalf
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "exec" {
  name               = "${var.name}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
resource "aws_iam_role_policy_attachment" "exec" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "secret" {
  role = aws_iam_role.exec.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = var.db_secret_arn }]
  })
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights" # per-service CPU, memory and running-task metrics (small extra cost)
    value = "enabled"
  }
}

# ----- load balancer: / goes to web, /api/* and /health go to api -----
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]
  idle_timeout       = 300 # SSE streams are long-lived; the API also sends a 20s heartbeat
}
resource "aws_lb_target_group" "api" {
  name                 = "${var.name}-api"
  port                 = 4000
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  health_check { path = "/health" }
}
resource "aws_lb_target_group" "web" {
  name                 = "${var.name}-web"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  health_check { path = "/" }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP" # add an HTTPS listener + ACM certificate once you own a domain
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    path_pattern { values = ["/api/*", "/health"] }
  }
}

# ----- task definitions -----
locals {
  log = { for a in local.apps : a => {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = aws_cloudwatch_log_group.logs.name
      "awslogs-region"        = var.region
      "awslogs-stream-prefix" = a
    }
  } }
}
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.exec.arn
  container_definitions = jsonencode([{
    name         = "api"
    image        = "${aws_ecr_repository.repo["api"].repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 4000 }]
    environment = [
      { name = "PGHOST", value = var.db_host },
      { name = "PGUSER", value = "naija" },
      { name = "PGDATABASE", value = "votes" },
      { name = "DB_SSL", value = "true" },
      { name = "REDIS_URL", value = "rediss://${var.redis_host}:6379" }
    ]
    secrets          = [{ name = "PGPASSWORD", valueFrom = var.db_secret_arn }]
    logConfiguration = local.log["api"]
  }])
}
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.exec.arn
  container_definitions = jsonencode([{
    name             = "web"
    image            = "${aws_ecr_repository.repo["web"].repository_url}:${var.image_tag}"
    essential        = true
    portMappings     = [{ containerPort = 80 }]
    logConfiguration = local.log["web"]
  }])
}
resource "aws_ecs_task_definition" "simulator" {
  family                   = "${var.name}-simulator"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.exec.arn
  container_definitions = jsonencode([{
    name      = "simulator"
    image     = "${aws_ecr_repository.repo["simulator"].repository_url}:${var.image_tag}"
    essential = true
    environment = [
      { name = "API_URL", value = "http://${aws_lb.this.dns_name}" },
      { name = "VOTES_PER_SEC", value = "15" }
    ]
    logConfiguration = local.log["simulator"]
  }])
}

# ----- services -----
resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_count
  launch_type     = "FARGATE"
  lifecycle {
    ignore_changes = [task_definition, desired_count] # pipeline and autoscaler own these after creation
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true # a deploy whose tasks keep failing health checks rolls back by itself
  }
  network_configuration {
    subnets         = var.app_subnet_ids
    security_groups = [var.api_sg_id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 4000
  }
  depends_on = [aws_lb_listener_rule.api]
}
resource "aws_ecs_service" "web" {
  name            = "web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  lifecycle {
    ignore_changes = [task_definition, desired_count] # pipeline and autoscaler own these after creation
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true # a deploy whose tasks keep failing health checks rolls back by itself
  }
  network_configuration {
    subnets         = var.app_subnet_ids
    security_groups = [var.web_sg_id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.http]
}
resource "aws_ecs_service" "simulator" {
  name            = "simulator"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.simulator.arn
  desired_count   = var.simulator_count
  launch_type     = "FARGATE"
  lifecycle {
    ignore_changes = [task_definition, desired_count] # pipeline and autoscaler own these after creation
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true # a deploy whose tasks keep failing health checks rolls back by itself
  }
  network_configuration {
    subnets         = var.app_subnet_ids
    security_groups = [var.sim_sg_id]
  }
}

output "alb_dns" { value = aws_lb.this.dns_name }
output "ecr_urls" { value = { for k, r in aws_ecr_repository.repo : k => r.repository_url } }

# ----- autoscaling: add API tasks when average CPU passes 60%, remove slowly -----
resource "aws_appautoscaling_target" "api" {
  min_capacity       = var.api_count
  max_capacity       = var.api_max
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${var.name}-api-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }
output "api_tg_suffix" { value = aws_lb_target_group.api.arn_suffix }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "exec_role_arn" { value = aws_iam_role.exec.arn }
