# Deploying Saenggak

Every push to `main` deploys the server and the web app with GitHub Actions
(`.github/workflows/deploy.yml`). The deploy does nothing until the one-time
setup below is done.

## One-time setup

1. **AWS account and region.** The default is `us-east-1`, where every model
   the server uses is available on Bedrock. Seoul (`ap-northeast-2`) is closer
   to Korean users; use it only if Bedrock offers Titan Text Embeddings v2 and
   Claude there.
2. **Run `aws-setup.sh` in AWS CloudShell** as an administrator, in that
   region. Upload the file through CloudShell's Actions > Upload file, then
   `bash aws-setup.sh`. It bootstraps CDK and creates a deploy role that only
   this repository's `main` branch can use, through short-lived tokens with no
   stored keys. It prints two values.
3. **Add them in GitHub** under Settings > Secrets and variables > Actions >
   Variables: `AWS_DEPLOY_ROLE_ARN` and `AWS_REGION`.
4. **Claude for the content filter.** Two routes; pick one with the
   `MODERATION_PROVIDER` variable in GitHub:
   - `bedrock` (default): Claude on Amazon Bedrock. In the Bedrock console,
     submit the Anthropic use-case form, then check that Claude Haiku 5.5
     answers in the playground. Some new accounts are blocked from Anthropic
     models until AWS support lifts it.
   - `anthropic`: the Claude API. Create a key at console.anthropic.com,
     then after the first deploy paste it as the value of the
     `ClaudeApiKeySecret` secret (named in the deploy summary) in the AWS
     Secrets Manager console. No redeploy is needed.

   Titan Text Embeddings v2 on Bedrock is used either way and needs no form.
   `MODERATION_MODEL` overrides the model id.
5. **Run the deploy**: Actions > Deploy > Run workflow, or push to `main`.
   The first run takes about 20 minutes, mostly for the database and
   CloudFront. The job summary shows the web address and the API address.

## What a deploy does

- Builds the Flutter web app and uploads it behind CloudFront, with a
  `config.json` that points it at this deploy's API and sign-in.
- Deploys the Lambdas, the API, Cognito and Aurora.
- Runs `backend/src/db/migrations/*.sql` that have not run yet. Add schema
  changes as new numbered files; never edit one that has been deployed.

## Before a public launch

- Cognito sends sign-up codes from its own address, limited to about 50
  emails a day. Set up Amazon SES with your domain and point the user pool at it.
- Add AWS WAF with per-IP rate rules in front of the API and CloudFront.
- Add a custom domain for the web app and API.
- Aurora is set to at least 0.5 ACU (roughly 45 USD a month even when idle).
- iOS and Android builds take the API settings with `--dart-define`; the
  deploy summary prints the exact command.
