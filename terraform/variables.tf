variable "region"          { default = "eu-west-1" }   # no opt-in needed; try af-south-1 after opting in
variable "name"            { default = "naija-vote" }
variable "single_nat"      { default = true }          # false = one NAT per AZ (resilient, pricier)
variable "db_multi_az"     { default = false }
variable "api_count"       { default = 2 }
variable "simulator_count" { default = 1 }
variable "github_repo" {
  description = "owner/repo allowed to deploy, e.g. ada/naija-vote"
  type        = string
}
variable "api_max" { default = 6 }
variable "alert_email" {
  description = "Where alarm emails go (you must click the confirmation link AWS sends)"
  type        = string
}
variable "db_backup_days" { default = 1 }