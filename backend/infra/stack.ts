import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import * as apigw from 'aws-cdk-lib/aws-apigatewayv2';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { HttpJwtAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as triggers from 'aws-cdk-lib/triggers';
import type { Construct } from 'constructs';

const here = path.dirname(fileURLToPath(import.meta.url));
const handlerPath = (name: string) => path.join(here, '..', 'src', 'handlers', `${name}.ts`);
const migrationsDir = path.join(here, '..', 'src', 'db', 'migrations');
/** The Flutter web build. Deployed when present; build it first with `flutter build web`. */
const webBuild = path.join(here, '..', '..', 'app', 'build', 'web');

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
      // The content filter's route ("bedrock" or "anthropic") and model, from
      // the MODERATION_PROVIDER and MODERATION_MODEL variables in GitHub.
      // Claude API until the account's Bedrock access to Anthropic models is lifted.
      MODERATION_PROVIDER: process.env.MODERATION_PROVIDER || 'anthropic',
      ...(process.env.MODERATION_MODEL ? { MODERATION_MODEL: process.env.MODERATION_MODEL } : {}),
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

    // Brings the schema up to date after every deploy, once the database exists.
    const migrateFn = new NodejsFunction(this, 'migrate', {
      entry: handlerPath('migrate'),
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      timeout: Duration.minutes(5),
      environment,
      bundling: {
        minify: true,
        commandHooks: {
          beforeBundling: () => [],
          beforeInstall: () => [],
          afterBundling: (_input: string, output: string) => [`cp -r "${migrationsDir}" "${output}/migrations"`],
        },
      },
    });
    db.grantDataApiAccess(migrateFn);
    new triggers.Trigger(this, 'Migrate', {
      handler: migrateFn,
      executeAfter: [db],
      executeOnHandlerChange: true,
      timeout: Duration.minutes(5),
    });

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
    // The Claude API key, for MODERATION_PROVIDER=anthropic. The deploy creates
    // it with a random placeholder; paste the real key in the Secrets Manager console.
    const claudeKey = new secretsmanager.Secret(this, 'ClaudeApiKey', {
      description: 'Claude API key for the Saenggak content filter (console.anthropic.com)',
    });
    claudeKey.grantRead(write);
    write.addEnvironment('ANTHROPIC_KEY_SECRET_ARN', claudeKey.secretArn);
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
      ['/me', M.PUT, writeIntegration],
      ['/users/{id}', M.GET, apiIntegration],
      ['/users/{id}/follow', M.PUT, apiIntegration],
      ['/users/{id}/follow', M.DELETE, apiIntegration],
    ];
    for (const [path, method, integration] of routes) http.addRoutes({ path, methods: [method], integration });

    // These limits are shared by every user of the API, so they only guard the
    // account against floods. Per-person limits are the hourly write limit in
    // the database and, before launch, per-IP rate rules in WAF.
    const stage = http.defaultStage?.node.defaultChild as apigw.CfnStage | undefined;
    stage?.addPropertyOverride('DefaultRouteSettings', { ThrottlingRateLimit: 500, ThrottlingBurstLimit: 1000 });

    // The web app: a private bucket behind CloudFront. config.json tells the
    // built app where the API is, so the same build works for any deploy.
    const site = new s3.Bucket(this, 'Web', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    const cdn = new cloudfront.Distribution(this, 'Cdn', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(site),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
      },
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
    });
    const config = {
      apiUrl: http.apiEndpoint,
      cognitoRegion: this.region,
      cognitoClientId: appClient.userPoolClientId,
    };
    new s3deploy.BucketDeployment(this, 'WebFiles', {
      destinationBucket: site,
      sources: [
        ...(existsSync(webBuild) ? [s3deploy.Source.asset(webBuild)] : []),
        s3deploy.Source.jsonData('config.json', config),
      ],
      distribution: cdn,
      memoryLimit: 512,
      // Revalidate on each load so a new deploy shows up at once; unchanged files answer 304.
      cacheControl: [s3deploy.CacheControl.fromString('no-cache')],
    });

    new CfnOutput(this, 'ClaudeApiKeySecret', { value: claudeKey.secretName });
    new CfnOutput(this, 'WebUrl', { value: `https://${cdn.distributionDomainName}` });
    new CfnOutput(this, 'ApiUrl', { value: http.apiEndpoint });
    new CfnOutput(this, 'UserPoolId', { value: users.userPoolId });
    new CfnOutput(this, 'UserPoolClientId', { value: appClient.userPoolClientId });
    new CfnOutput(this, 'DbClusterArn', { value: db.clusterArn });
  }
}
