#!/usr/bin/env bash
# One-time AWS setup for Saenggak deploys from GitHub Actions.
#
# Run it in AWS CloudShell (the >_ icon at the top of the AWS console), signed
# in as an administrator, in the region you will deploy to:
#   bash aws-setup.sh
# It is safe to run again.
#
# It does three things:
#   1. Prepares the account and region for CDK (cdk bootstrap).
#   2. Lets GitHub Actions sign in to AWS with short-lived tokens (no stored keys).
#   3. Creates a role that only this repository's main branch can use, and that
#      can only deploy through CDK's own roles.
set -euo pipefail

REPO="${REPO:-jmbcorp-01/Saenggak}"
# GitHub now puts the owner's and repository's numeric ids in the token's
# subject ("repo:owner@123/name@456:..."), so a renamed or re-created
# repository with the same name cannot use the role.
REPO_WITH_IDS="${REPO_WITH_IDS:-jmbcorp-01@146903547/Saenggak@1467445621}"
ROLE_NAME="${ROLE_NAME:-saenggak-github-deploy}"
REGION="${AWS_REGION:-$(aws configure get region || echo us-east-1)}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"

echo "Account $ACCOUNT, region $REGION, repository $REPO"

echo "1/3 CDK bootstrap"
npx --yes aws-cdk@2.1149.0 bootstrap "aws://$ACCOUNT/$REGION"

echo "2/3 GitHub sign-in (OIDC provider)"
PROVIDER_ARN="arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com >/dev/null
fi

echo "3/3 Deploy role"
TRUST=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "$PROVIDER_ARN" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:$REPO_WITH_IDS:ref:refs/heads/main",
          "repo:$REPO_WITH_IDS:environment:production"
        ]
      }
    }
  }]
}
JSON
)
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST"
else
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST" >/dev/null
fi
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name cdk-deploy --policy-document "$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::$ACCOUNT:role/cdk-*"
  }]
}
JSON
)"

echo
echo "Done. In GitHub, open the repository's Settings > Secrets and variables > Actions > Variables and add:"
echo "  AWS_DEPLOY_ROLE_ARN = arn:aws:iam::$ACCOUNT:role/$ROLE_NAME"
echo "  AWS_REGION          = $REGION"
