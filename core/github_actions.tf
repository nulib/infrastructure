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

      values = flatten([
        for org, repos in var.oidc_github_repositories : [
          for repo in repos : "repo:${org}/${repo}:*"
        ]
      ])
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
