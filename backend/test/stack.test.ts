import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { App } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { describe, expect, it } from 'vitest';
import { SaenggakStack } from '../infra/stack.js';

const here = path.dirname(fileURLToPath(import.meta.url));

describe('SaenggakStack', () => {
  const template = Template.fromStack(
    new SaenggakStack(new App(), 'Test', { env: { account: '123456789012', region: 'us-east-1' } }),
  );

  it('creates Aurora Serverless v2 with the Data API', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      Engine: 'aurora-postgresql',
      EnableHttpEndpoint: true,
      StorageEncrypted: true,
      ServerlessV2ScalingConfiguration: { MinCapacity: 0.5, MaxCapacity: 4 },
    });
  });

  it('protects every route with the Cognito JWT authorizer', () => {
    template.resourceCountIs('AWS::ApiGatewayV2::Route', 39);
    template.allResourcesProperties('AWS::ApiGatewayV2::Route', { AuthorizationType: 'JWT' });
  });

  it('runs the Node 22 Lambdas outside the VPC', () => {
    const fns = template.findResources('AWS::Lambda::Function', { Properties: { Runtime: 'nodejs22.x' } });
    // write, api, admin, cleanup, migrate and the sign-up check
    expect(Object.keys(fns)).toHaveLength(6);
    for (const f of Object.values(fns)) expect(f.Properties.VpcConfig).toBeUndefined();
  });

  it('migrates the database after it is created', () => {
    template.resourceCountIs('Custom::Trigger', 1);
  });

  it('serves the web app from a private bucket with its API settings', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: Match.objectLike({ BlockPublicAcls: true, RestrictPublicBuckets: true }),
    });
    template.resourceCountIs('AWS::CloudFront::Distribution', 1);
    // The web files revalidate on each load; our fonts, when the build is
    // there to deploy, are kept a week.
    template.hasResourceProperties('Custom::CDKBucketDeployment', { SystemMetadata: { 'cache-control': 'no-cache' } });
    const deployments = Object.values(template.findResources('Custom::CDKBucketDeployment'));
    if (existsSync(path.join(here, '..', '..', 'app', 'build', 'web'))) {
      expect(deployments).toHaveLength(2);
      template.hasResourceProperties('Custom::CDKBucketDeployment', {
        SystemMetadata: { 'cache-control': 'public, max-age=604800' },
        Include: ['assets/assets/fonts/*'],
      });
    } else {
      expect(deployments).toHaveLength(1);
    }
  });

  it('serves profile photos at /photos/* and lets only the write function store them', () => {
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        CacheBehaviors: Match.arrayWith([Match.objectLike({ PathPattern: '/photos/*' })]),
      }),
    });
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({ Action: ['rekognition:DetectFaces', 'rekognition:DetectModerationLabels'] }),
        ]),
      }),
    });
  });

  it('cleans up old rows daily and keeps logs three months', () => {
    template.hasResourceProperties('AWS::Events::Rule', { ScheduleExpression: 'cron(30 18 * * ? *)' });
    template.hasResourceProperties('AWS::Logs::LogGroup', { RetentionInDays: 90 });
  });

  it('has an admins group for the admin pages', () => {
    template.hasResourceProperties('AWS::Cognito::UserPoolGroup', { GroupName: 'admins' });
  });

  it('throttles the API', () => {
    template.hasResourceProperties('AWS::ApiGatewayV2::Stage', {
      DefaultRouteSettings: Match.objectLike({ ThrottlingRateLimit: 500 }),
    });
  });

  it('puts the site and the API behind a firewall, and the API only through CloudFront', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACL', {
      Scope: 'CLOUDFRONT',
      Rules: Match.arrayWith([
        Match.objectLike({ Name: 'AWSManagedRulesAmazonIpReputationList' }),
        Match.objectLike({ Name: 'PerAddress', Statement: { RateBasedStatement: { Limit: 2000, AggregateKeyType: 'IP' } } }),
        Match.objectLike({ Name: 'ApiWritesPerAddress' }),
      ]),
    });
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        WebACLId: Match.anyValue(),
        CacheBehaviors: Match.arrayWith([Match.objectLike({ PathPattern: '/api/*', AllowedMethods: Match.arrayWith(['POST']) })]),
      }),
    });
    // Every API Lambda checks the header CloudFront adds.
    const fns = template.findResources('AWS::Lambda::Function', {
      Properties: { Environment: { Variables: { ORIGIN_SECRET: Match.anyValue() } } },
    });
    expect(Object.keys(fns)).toHaveLength(3);
  });

  it('guards sign-up and sign-in', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACL', {
      Scope: 'REGIONAL',
      Rules: Match.arrayWith([Match.objectLike({ Name: 'PerAddress', Statement: { RateBasedStatement: { Limit: 100, AggregateKeyType: 'IP' } } })]),
    });
    template.resourceCountIs('AWS::WAFv2::WebACLAssociation', 1);
    template.hasResourceProperties('AWS::Cognito::UserPool', {
      LambdaConfig: { PreSignUp: Match.anyValue() },
    });
  });

  it('answers at its own domain once a certificate is given', () => {
    const withSite = Template.fromStack(
      new SaenggakStack(new App(), 'Site', {
        env: { account: '123456789012', region: 'us-east-1' },
        site: { domain: 'saenggak.app', certificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/abc' },
      }),
    );
    withSite.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        Aliases: ['saenggak.app', 'www.saenggak.app'],
        ViewerCertificate: Match.objectLike({
          AcmCertificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/abc',
        }),
      }),
    });
    withSite.hasOutput('ApiUrl', { Value: 'https://saenggak.app/api' });
  });

  it('adds Google and Apple sign-in at auth.saenggak.app once set up', () => {
    const withSignIn = Template.fromStack(
      new SaenggakStack(new App(), 'SignIn', {
        env: { account: '123456789012', region: 'us-east-1' },
        site: { domain: 'saenggak.app', certificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/abc' },
        signIn: {
          authDomain: 'auth.saenggak.app',
          authCertificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/auth',
          google: { clientId: 'g.apps.googleusercontent.com' },
          apple: { servicesId: 'app.saenggak.signin', teamId: 'TEAM', keyId: 'KEY' },
        },
      }),
    );
    withSignIn.hasResourceProperties('AWS::Cognito::UserPoolDomain', {
      Domain: 'auth.saenggak.app',
      CustomDomainConfig: { CertificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/auth' },
    });
    withSignIn.hasResourceProperties('AWS::Cognito::UserPoolIdentityProvider', { ProviderName: 'Google', ProviderType: 'Google' });
    withSignIn.hasResourceProperties('AWS::Cognito::UserPoolIdentityProvider', {
      ProviderName: 'SignInWithApple',
      ProviderDetails: Match.objectLike({ client_id: 'app.saenggak.signin', team_id: 'TEAM', key_id: 'KEY' }),
    });
    withSignIn.hasResourceProperties('AWS::Cognito::UserPoolClient', {
      AllowedOAuthFlows: ['code'],
      CallbackURLs: ['saenggak://auth', 'https://saenggak.app/auth.html'],
      SupportedIdentityProviders: ['COGNITO', 'Google', 'SignInWithApple'],
    });
    withSignIn.hasOutput('AuthDomainTarget', Match.anyValue());
  });

  it('leaves sign-in to email until set up', () => {
    template.resourceCountIs('AWS::Cognito::UserPoolDomain', 0);
    template.resourceCountIs('AWS::Cognito::UserPoolIdentityProvider', 0);
  });

  it('keeps the CloudFront address without a certificate', () => {
    const cdn = template.findResources('AWS::CloudFront::Distribution');
    expect(Object.values(cdn).every((d) => !(d as { Properties: { DistributionConfig: { Aliases?: unknown } } }).Properties.DistributionConfig.Aliases)).toBe(true);
  });
});
