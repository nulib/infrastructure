locals {
  repo_pairs = { for p in flatten([
    for org, repos in var.oidc_github_repositories : [for r in repos : { org = org, repo = r }]
  ]) : "${p.org}/${p.repo}" => p }
}

data "http" "org" {
  for_each        = toset(keys(var.oidc_github_repositories))
  url             = "https://api.github.com/orgs/${each.key}"
  request_headers = { Accept = "application/vnd.github+json" }
}

data "github_repository" "repo" {
  for_each  = local.repo_pairs
  full_name = each.key
}

locals {
  org_ids = { for org in keys(var.oidc_github_repositories) : org => jsondecode(data.http.org[org].response_body).id }

  subs = flatten([
    for key, p in local.repo_pairs : [
      "repo:${p.org}/${p.repo}:*",
      "repo:${p.org}@${local.org_ids[p.org]}/${p.repo}@${data.github_repository.repo[key].repo_id}:*",
    ]
  ])
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid = "1"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = local.subs
    }

  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

}

resource "aws_iam_role" "github" {
  name                 = "github-actions-role"
  description          = "IAM role to enable GitHub OIDC access"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600
  path                 = "/"

}

resource "aws_iam_role_policy_attachment" "policy" {
  role       = aws_iam_role.github.id
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
