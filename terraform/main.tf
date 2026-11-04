provider "aws" {
  region = var.region
  default_tags { tags = { Project = var.name, ManagedBy = "terraform" } }
}
data "aws_availability_zones" "az" { state = "available" }

module "network" {
  source     = "./modules/network"
  name       = var.name
  azs        = slice(data.aws_availability_zones.az.names, 0, 2)
  single_nat = var.single_nat
}
module "security" {
  source = "./modules/security"
  name   = var.name
  vpc_id = module.network.vpc_id
}
module "data" {
  source             = "./modules/data"
  name               = var.name
  data_subnet_ids    = module.network.data_subnet_ids
  postgres_sg_id     = module.security.postgres_sg_id
  redis_sg_id        = module.security.redis_sg_id
  multi_az           = var.db_multi_az
  backup_days = var.db_backup_days
}
module "compute" {
  source            = "./modules/compute"
  name              = var.name
  region            = var.region
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  app_subnet_ids    = module.network.app_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  api_sg_id         = module.security.api_sg_id
  web_sg_id         = module.security.web_sg_id
  sim_sg_id         = module.security.sim_sg_id
  db_host           = module.data.db_host
  db_secret_arn     = module.data.db_secret_arn
  redis_host        = module.data.redis_host
  api_count         = var.api_count
  api_max           = var.api_max
  simulator_count   = var.simulator_count
}

module "observability" {
  source         = "./modules/observability"
  name           = var.name
  region         = var.region
  alert_email    = var.alert_email
  alb_arn_suffix = module.compute.alb_arn_suffix
  api_tg_suffix  = module.compute.api_tg_suffix
  cluster_name   = module.compute.cluster_name
  db_identifier  = module.data.db_identifier
  redis_id       = module.data.redis_id
}
