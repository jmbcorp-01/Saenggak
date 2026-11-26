import { App } from 'aws-cdk-lib';
import { SITE } from './site.js';
import { SaenggakStack } from './stack.js';

const app = new App();
new SaenggakStack(app, 'Saenggak', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION ?? 'us-east-1' },
  site: SITE.certificateArn ? SITE : undefined,
});
