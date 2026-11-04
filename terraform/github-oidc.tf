# Lets GitHub Actions deploy WITHOUT any stored AWS keys: GitHub proves who it is with a
# short-lived token, and AWS hands back temporary credentials for this one role.
data "aws_caller_identity" "me" {}

# One GitHub OIDC provider is allowed per AWS account. If yours already exists, replace this
# resource with: data "aws_iam_openid_connect_provider" "github" { url = "https://token.actions.githubusercontent.com" }
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "gh_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"] # only the main branch of your repo
    }
  }
}
resource "aws_iam_role" "deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.gh_trust.json
}

# Least privilege: push images to our repos, and redeploy our services. Nothing else.
data "aws_iam_policy_document" "gh_perms" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages"
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.me.account_id}:repository/${var.name}/*"]
  }
  statement {
    actions   = ["ecs:UpdateService"]
    resources = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.me.account_id}:service/${var.name}/*"]
  }
  statement {
    actions   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"] # these three actions do not support resource-level restrictions
  }
  statement {
    actions   = ["iam:PassRole"] # registering a task definition hands ECS the execution role
    resources = [module.compute.exec_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role_policy" "deploy" {
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.gh_perms.json
}
