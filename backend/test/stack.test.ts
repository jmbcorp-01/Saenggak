import { App } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { describe, expect, it } from 'vitest';
import { SaenggakStack } from '../infra/stack.js';

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
    template.resourceCountIs('AWS::ApiGatewayV2::Route', 11);
    template.allResourcesProperties('AWS::ApiGatewayV2::Route', { AuthorizationType: 'JWT' });
  });

  it('runs the Node 22 Lambdas outside the VPC', () => {
    const fns = template.findResources('AWS::Lambda::Function', { Properties: { Runtime: 'nodejs22.x' } });
    // write, api and migrate
    expect(Object.keys(fns)).toHaveLength(3);
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
    template.resourceCountIs('Custom::CDKBucketDeployment', 1);
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

  it('throttles the API', () => {
    template.hasResourceProperties('AWS::ApiGatewayV2::Stage', {
      DefaultRouteSettings: Match.objectLike({ ThrottlingRateLimit: 500 }),
    });
  });
});
