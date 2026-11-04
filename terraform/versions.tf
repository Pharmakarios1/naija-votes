terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
  # Next step: remote state so teammates and CI share it
  # backend "s3" { bucket = "YOUR-STATE-BUCKET" key = "naija-vote/dev.tfstate" region = "eu-west-1" use_lockfile = true }
}
