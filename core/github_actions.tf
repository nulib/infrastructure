module "oidc-with-github-actions" {
  source  = "thetestlabs/oidc-with-github-actions/aws"
  version = "0.1.4"

  github_org            = "nulib"
  github_repositories   = var.oidc_github_repositories
  iam_role_name         = "github-actions-role"
  iam_role_policy       = "AdministratorAccess"
}
