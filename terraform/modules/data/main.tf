variable "name" {}
variable "data_subnet_ids" { type = list(string) }
variable "postgres_sg_id" {}
variable "redis_sg_id" {}
variable "multi_az" { default = false }
variable "backup_days" { default = 1 }

resource "random_password" "db" {
  length  = 24
  special = false
}
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}/db-password"
  recovery_window_in_days = 0 # lets you destroy and recreate while practising
}
resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = random_password.db.result
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.data_subnet_ids
}
resource "aws_db_instance" "this" {
  identifier              = "${var.name}-pg"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  db_name                 = "votes"
  username                = "naija"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [var.postgres_sg_id]
  multi_az                = var.multi_az
  storage_encrypted       = true
  publicly_accessible     = false
  backup_retention_period = var.backup_days
  skip_final_snapshot     = true # practice only; set false for anything real
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis"
  subnet_ids = var.data_subnet_ids
}
resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = "${var.name}-redis"
  description                = "Pub/sub bus for live result updates"
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [var.redis_sg_id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true # clients must use rediss://
}

output "db_host" { value = aws_db_instance.this.address }
output "db_secret_arn" { value = aws_secretsmanager_secret.db.arn }
output "redis_host" { value = aws_elasticache_replication_group.this.primary_endpoint_address }
output "db_identifier" { value = aws_db_instance.this.identifier }
output "redis_id" { value = aws_elasticache_replication_group.this.replication_group_id }
