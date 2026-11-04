output "app_url"  { value = "http://${module.compute.alb_dns}" }
output "ecr_repos" { value = module.compute.ecr_urls }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "dashboard_url" { value = module.observability.dashboard_url }
