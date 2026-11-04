variable "name" {}
variable "vpc_id" {}

# Each tier only accepts traffic from the tier in front of it (referenced by security group, not IP)
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_security_group" "api" {
  name_prefix = "${var.name}-api-"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_security_group" "web" {
  name_prefix = "${var.name}-web-"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}
# Fake voters: outbound only, and no database access
resource "aws_security_group" "sim" {
  name_prefix = "${var.name}-sim-"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_security_group" "postgres" {
  name_prefix = "${var.name}-pg-"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-redis-"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }
  lifecycle { create_before_destroy = true }
}

output "alb_sg_id" { value = aws_security_group.alb.id }
output "api_sg_id" { value = aws_security_group.api.id }
output "web_sg_id" { value = aws_security_group.web.id }
output "sim_sg_id" { value = aws_security_group.sim.id }
output "postgres_sg_id" { value = aws_security_group.postgres.id }
output "redis_sg_id" { value = aws_security_group.redis.id }
