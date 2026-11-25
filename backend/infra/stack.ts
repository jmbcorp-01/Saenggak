import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import * as apigw from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpJwtAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import * as rds from 'aws-cdk-lib/aws-rds';
import type { Construct } from 'constructs';

const here = path.dirname(fileURLToPath(import.meta.url));
const handlerPath = (name: string) => path.join(here, '..', 'src', 'handlers', `${name}.ts`);

/**
 * Everything the MVP needs: sign-in (Cognito), the database (Aurora
 * Serverless v2 PostgreSQL with pgvector, reached through the Data API so the
 * Lambdas need no VPC), two Lambdas behind an HTTP API with a JWT check.
 */
export class SaenggakStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Sign-in: email and password. Social sign-in can be added to this pool later.
    const users = new cognito.UserPool(this, 'Users', {
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      autoVerify: { email: true },
      passwordPolicy: { minLength: 10, requireSymbols: false },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: RemovalPolicy.RETAIN,
    });
    const appClient = users.addClient('App', {
      authFlows: { userSrp: true, userPassword: true },
      preventUserExistenceErrors: true,
    });

    // Database in isolated subnets; nothing in it is reachable from the internet.
    const vpc = new ec2.Vpc(this, 'Vpc', {
      maxAzs: 2,
      natGateways: 0,
      subnetConfiguration: [{ name: 'db', subnetType: ec2.SubnetType.PRIVATE_ISOLATED }],
    });
    const db = new rds.DatabaseCluster(this, 'Db', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({ version: rds.AuroraPostgresEngineVersion.VER_17_6 }),
      writer: rds.ClusterInstance.serverlessV2('writer'),
      serverlessV2MinCapacity: 0.5,
      serverlessV2MaxCapacity: 4,
      enableDataApi: true,
      defaultDatabaseName: 'saenggak',
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      storageEncrypted: true,
      removalPolicy: RemovalPolicy.SNAPSHOT,
    });

    const environment = {
      DB_CLUSTER_ARN: db.clusterArn,
      DB_SECRET_ARN: db.secret!.secretArn,
      DB_NAME: 'saenggak',
    };
    const fn = (name: string, timeout = 10) => {
      const f = new NodejsFunction(this, name, {
        entry: handlerPath(name),
        runtime: lambda.Runtime.NODEJS_22_X,
        architecture: lambda.Architecture.ARM_64,
        memorySize: 512,
        timeout: Duration.seconds(timeout),
        environment,
        bundling: { minify: true, sourceMap: true },
      });
      db.grantDataApiAccess(f);
      return f;
    };

    // Writing waits on moderation and embedding, so it gets a longer timeout.
    const write = fn('write', 30);
    const api = fn('api', 15);

    write.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['bedrock:InvokeModel'],
        resources: [`arn:aws:bedrock:${this.region}::foundation-model/amazon.titan-embed-text-v2:0`],
      }),
    );
    // Claude on Bedrock is called through the bedrock-mantle endpoint (SigV4 service "bedrock-mantle").
    // Narrow this to the exact actions and model once the account's Bedrock access is set up.
    write.addToRolePolicy(new iam.PolicyStatement({ actions: ['bedrock-mantle:*'], resources: ['*'] }));
    api.addToRolePolicy(new iam.PolicyStatement({ actions: ['translate:TranslateText'], resources: ['*'] }));

    const http = new apigw.HttpApi(this, 'Api', {
      defaultAuthorizer: new HttpJwtAuthorizer('Jwt', users.userPoolProviderUrl, {
        jwtAudience: [appClient.userPoolClientId],
      }),
      corsPreflight: {
        allowOrigins: ['*'],
        allowMethods: [
          apigw.CorsHttpMethod.GET,
          apigw.CorsHttpMethod.POST,
          apigw.CorsHttpMethod.PUT,
          apigw.CorsHttpMethod.PATCH,
          apigw.CorsHttpMethod.DELETE,
        ],
        allowHeaders: ['authorization', 'content-type'],
      },
    });
    const M = apigw.HttpMethod;
    const writeIntegration = new HttpLambdaIntegration('Write', write);
    const apiIntegration = new HttpLambdaIntegration('ApiFn', api);
    const routes: [string, apigw.HttpMethod, HttpLambdaIntegration][] = [
      ['/posts', M.POST, writeIntegration],
      ['/posts/{id}', M.PATCH, writeIntegration],
      ['/posts/{id}', M.DELETE, apiIntegration],
      ['/posts/{id}/empathy', M.POST, apiIntegration],
      ['/feed', M.GET, apiIntegration],
      ['/me', M.GET, apiIntegration],
      ['/me', M.PUT, apiIntegration],
      ['/users/{id}', M.GET, apiIntegration],
      ['/users/{id}/follow', M.PUT, apiIntegration],
      ['/users/{id}/follow', M.DELETE, apiIntegration],
    ];
    for (const [path, method, integration] of routes) http.addRoutes({ path, methods: [method], integration });

    // Rate limits on the default stage slow down scraping; WAF and CloudFront come before launch.
    const stage = http.defaultStage?.node.defaultChild as apigw.CfnStage | undefined;
    stage?.addPropertyOverride('DefaultRouteSettings', { ThrottlingRateLimit: 20, ThrottlingBurstLimit: 40 });

    new CfnOutput(this, 'ApiUrl', { value: http.apiEndpoint });
    new CfnOutput(this, 'UserPoolId', { value: users.userPoolId });
    new CfnOutput(this, 'UserPoolClientId', { value: appClient.userPoolClientId });
    new CfnOutput(this, 'DbClusterArn', { value: db.clusterArn });
  }
}
