import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CfnOutput, Duration, RemovalPolicy, SecretValue, Stack, type StackProps } from 'aws-cdk-lib';
import * as apigw from 'aws-cdk-lib/aws-apigatewayv2';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { HttpJwtAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as triggers from 'aws-cdk-lib/triggers';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import type { Construct } from 'constructs';
import type { SignInSettings } from './site.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const handlerPath = (name: string) => path.join(here, '..', 'src', 'handlers', `${name}.ts`);
const migrationsDir = path.join(here, '..', 'src', 'db', 'migrations');
/** The Flutter web build. Deployed when present; build it first with `flutter build web`. */
const webBuild = path.join(here, '..', '..', 'app', 'build', 'web');

/**
 * Everything the MVP needs: sign-in (Cognito), the database (Aurora
 * Serverless v2 PostgreSQL with pgvector, reached through the Data API so the
 * Lambdas need no VPC), three Lambdas (write, api, admin) behind an HTTP API with a JWT check.
 */
export interface SaenggakProps extends StackProps {
  /** The site's own domain and its us-east-1 certificate; without it, only the CloudFront address. */
  site?: { domain: string; certificateArn: string };
  /** Google and Apple sign-in through Cognito's sign-in pages; see infra/site.ts. */
  signIn?: SignInSettings;
}

/** Where the sign-in pages send people back: the app's own link, and the web app's page. */
export const APP_CALLBACK = 'saenggak://auth';


export class SaenggakStack extends Stack {
  constructor(scope: Construct, id: string, props?: SaenggakProps) {
    super(scope, id, props);
    const domain = props?.site;

    // Sign-in: email and password, and Google and Apple once set up (infra/site.ts).
    const users = new cognito.UserPool(this, 'Users', {
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      autoVerify: { email: true },
      passwordPolicy: { minLength: 10, requireSymbols: false },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: RemovalPolicy.RETAIN,
    });
    const signIn = props?.signIn;
    const providers = signIn ? this.socialSignIn(users, signIn) : [];
    const callbacks = [APP_CALLBACK, ...(domain ? [`https://${domain.domain}/auth.html`] : [])];
    const appClient = users.addClient('App', {
      authFlows: { userSrp: true, userPassword: true },
      preventUserExistenceErrors: true,
      ...(signIn && {
        oAuth: {
          flows: { authorizationCodeGrant: true },
          scopes: [cognito.OAuthScope.OPENID, cognito.OAuthScope.EMAIL, cognito.OAuthScope.COGNITO_ADMIN],
          callbackUrls: callbacks,
          logoutUrls: callbacks,
        },
        supportedIdentityProviders: [
          cognito.UserPoolClientIdentityProvider.COGNITO,
          ...providers.map((p) => p.provider),
        ],
      }),
    });
    for (const p of providers) appClient.node.addDependency(p.idp);
    const authDomain = signIn
      ? users.addDomain('Auth', {
          customDomain: {
            domainName: signIn.authDomain,
            certificate: acm.Certificate.fromCertificateArn(this, 'AuthCertificate', signIn.authCertificateArn),
          },
        })
      : undefined;
    // People in this group can use the admin pages. Add someone with
    // aws cognito-idp admin-add-user-to-group (see deploy/README.md).
    new cognito.CfnUserPoolGroup(this, 'Admins', {
      userPoolId: users.userPoolId,
      groupName: 'admins',
      description: 'Saenggak admins: review held posts, suspend people, remove posts and photos',
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
        // More memory also means more CPU, which shortens cold starts.
        memorySize: 1024,
        timeout: Duration.seconds(timeout),
        environment,
        bundling: { minify: true, sourceMap: true },
        // Access and error logs are kept three months, as the privacy policy says.
        logGroup: new logs.LogGroup(this, `${name}Logs`, {
          retention: logs.RetentionDays.THREE_MONTHS,
          removalPolicy: RemovalPolicy.DESTROY,
        }),
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
    const admin = fn('admin', 15);
    // Deletes old rate-limit rows, admin logs and resolved reports each day.
    new events.Rule(this, 'DailyCleanup', {
      schedule: events.Schedule.cron({ hour: '18', minute: '30' }), // 03:30 in Korea
      targets: [new targets.LambdaFunction(fn('cleanup', 60))],
    });

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
    // Searching posts by meaning embeds the search words.
    api.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['bedrock:InvokeModel'],
        resources: [`arn:aws:bedrock:${this.region}::foundation-model/amazon.titan-embed-text-v2:0`],
      }),
    );

    // Sign-ups from throwaway mail services are refused before a code is sent.
    const preSignUp = new NodejsFunction(this, 'preSignUp', {
      entry: handlerPath('preSignUp'),
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      timeout: Duration.seconds(5),
      bundling: { minify: true },
    });
    users.addTrigger(cognito.UserPoolOperation.PRE_SIGN_UP, preSignUp);
    // A first Google or Apple sign-in joins the email account with the same
    // address, making one if there is none. The pool's ARN would make a loop
    // (the pool names this function), so the grant covers this account's pools.
    preSignUp.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          'cognito-idp:ListUsers',
          'cognito-idp:AdminCreateUser',
          'cognito-idp:AdminSetUserPassword',
          'cognito-idp:AdminLinkProviderForUser',
        ],
        resources: [`arn:aws:cognito-idp:${this.region}:${this.account}:userpool/*`],
      }),
    );

    // Only CloudFront, behind the firewall, may call the API: it adds this
    // secret header, and the Lambdas refuse requests without it.
    const originSecret = new secretsmanager.Secret(this, 'OriginSecret', {
      description: 'Header value CloudFront adds to API requests so the API answers only through the CDN',
      generateSecretString: { excludePunctuation: true, passwordLength: 40 },
    });
    for (const f of [write, api, admin]) f.addEnvironment('ORIGIN_SECRET', originSecret.secretValue.unsafeUnwrap());

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
    const adminIntegration = new HttpLambdaIntegration('AdminFn', admin);
    const routes: [string, apigw.HttpMethod, HttpLambdaIntegration][] = [
      ['/posts', M.POST, writeIntegration],
      ['/posts/{id}', M.PATCH, writeIntegration],
      ['/posts/{id}', M.DELETE, apiIntegration],
      ['/posts/{id}/empathy', M.POST, apiIntegration],
      ['/feed', M.GET, apiIntegration],
      ['/posts/{id}', M.GET, apiIntegration],
      ['/posts/{id}/bookmark', M.PUT, apiIntegration],
      ['/posts/{id}/bookmark', M.DELETE, apiIntegration],
      ['/bookmarks', M.GET, apiIntegration],
      ['/search/users', M.GET, apiIntegration],
      ['/search/posts', M.GET, apiIntegration],
      ['/me/export', M.GET, apiIntegration],
      ['/me/human-check', M.GET, apiIntegration],
      ['/me/human-check', M.POST, apiIntegration],
      ['/me', M.GET, apiIntegration],
      ['/me', M.PUT, writeIntegration],
      ['/me', M.DELETE, apiIntegration],
      ['/me/photo', M.PUT, writeIntegration],
      ['/users/{id}', M.GET, apiIntegration],
      ['/users/{id}/follow', M.PUT, apiIntegration],
      ['/users/{id}/follow', M.DELETE, apiIntegration],
      ['/users/{id}/alerts', M.PUT, apiIntegration],
      ['/users/{id}/alerts', M.DELETE, apiIntegration],
      ['/users/{id}/block', M.PUT, apiIntegration],
      ['/users/{id}/block', M.DELETE, apiIntegration],
      ['/users/{id}/report', M.POST, apiIntegration],
      ['/posts/{id}/report', M.POST, apiIntegration],
      ['/me/blocks', M.GET, apiIntegration],
      ['/notifications', M.GET, apiIntegration],
      ['/notifications/seen', M.POST, apiIntegration],
      // Admin pages. The admin function refuses anyone outside the admins group.
      ['/admin/stats', M.GET, adminIntegration],
      ['/admin/review', M.GET, adminIntegration],
      ['/admin/posts/{id}/review', M.POST, adminIntegration],
      ['/admin/posts/{id}/remove', M.POST, adminIntegration],
      ['/admin/users', M.GET, adminIntegration],
      ['/admin/users/{id}/suspension', M.PUT, adminIntegration],
      ['/admin/users/{id}/photo', M.DELETE, adminIntegration],
      ['/admin/reports', M.GET, adminIntegration],
      ['/admin/reports/{id}/resolve', M.POST, adminIntegration],
    ];
    for (const [path, method, integration] of routes) http.addRoutes({ path, methods: [method], integration });

    // These limits are shared by every user of the API, so they only guard the
    // account against floods. Per-person limits are the hourly write limit and
    // the activity risk score in the database; per-IP limits are in the firewall.
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
    const edgeFirewall = this.region === 'us-east-1' ? this.firewall('EdgeFirewall', 'CLOUDFRONT') : undefined;
    const cdn = new cloudfront.Distribution(this, 'Cdn', {
      webAclId: edgeFirewall?.attrArn,
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(site),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
      },
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
      ...(domain && {
        domainNames: [domain.domain, `www.${domain.domain}`],
        certificate: acm.Certificate.fromCertificateArn(this, 'SiteCertificate', domain.certificateArn),
      }),
    });
    // Where people reach the site: its own domain once set, else CloudFront's.
    const webHost = domain ? domain.domain : cdn.distributionDomainName;
    // Profile photos: private bucket, served read-only through the same CDN at /photos/*.
    // Only the write function stores them, after the face and moderation checks.
    const photos = new s3.Bucket(this, 'Photos', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      removalPolicy: RemovalPolicy.RETAIN,
    });
    cdn.addBehavior('/photos/*', origins.S3BucketOrigin.withOriginAccessControl(photos), {
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
    });
    // The API at /api/*, through the firewall, never cached. The prefix is
    // dropped before the request reaches API Gateway.
    const stripApi = new cloudfront.Function(this, 'StripApiPrefix', {
      runtime: cloudfront.FunctionRuntime.JS_2_0,
      code: cloudfront.FunctionCode.fromInline(
        "function handler(event) { var r = event.request; r.uri = r.uri.replace(/^\\/api/, '') || '/'; return r; }",
      ),
    });
    cdn.addBehavior(
      '/api/*',
      new origins.HttpOrigin(`${http.httpApiId}.execute-api.${this.region}.${this.urlSuffix}`, {
        customHeaders: { 'x-origin-verify': originSecret.secretValue.unsafeUnwrap() },
      }),
      {
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        // Nothing is cached; the sign-in token and query go to the API.
        cachePolicy: new cloudfront.CachePolicy(this, 'ApiNoCache', {
          defaultTtl: Duration.seconds(0),
          minTtl: Duration.seconds(0),
          maxTtl: Duration.seconds(1),
          headerBehavior: cloudfront.CacheHeaderBehavior.allowList('Authorization'),
          queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
        }),
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
        functionAssociations: [{ function: stripApi, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }],
      },
    );
    const apiUrl = `https://${webHost}/api`;

    // Sign-up and sign-in: known bad addresses and bursts from one address are stopped.
    new wafv2.CfnWebACLAssociation(this, 'SignInFirewall', {
      resourceArn: users.userPoolArn,
      webAclArn: this.firewall('SignInFirewallAcl', 'REGIONAL', 100).attrArn,
    });

    photos.grantPut(write);
    photos.grantDelete(write);
    photos.grantDelete(admin);
    photos.grantDelete(api);
    // Account deletion removes the sign-in account as well.
    api.addToRolePolicy(new iam.PolicyStatement({ actions: ['cognito-idp:AdminDeleteUser'], resources: [users.userPoolArn] }));
    api.addEnvironment('USER_POOL_ID', users.userPoolId);
    write.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['rekognition:DetectFaces', 'rekognition:DetectModerationLabels'],
        resources: ['*'],
      }),
    );
    for (const f of [write, api, admin]) f.addEnvironment('PHOTO_BUCKET', photos.bucketName);
    for (const f of [write, api, admin]) f.addEnvironment('PHOTO_BASE_URL', `https://${webHost}`);

    const config = {
      apiUrl,
      cognitoRegion: this.region,
      cognitoClientId: appClient.userPoolClientId,
      ...(signIn && { authDomain: signIn.authDomain, signInWith: providers.map((p) => p.name) }),
    };
    // Our own font files rarely change and are the largest download, so
    // browsers keep them a week instead of asking again on every visit.
    const fonts = 'assets/assets/fonts/*';
    new s3deploy.BucketDeployment(this, 'WebFiles', {
      destinationBucket: site,
      sources: [
        ...(existsSync(webBuild) ? [s3deploy.Source.asset(webBuild)] : []),
        s3deploy.Source.jsonData('config.json', config),
      ],
      exclude: [fonts],
      distribution: cdn,
      memoryLimit: 512,
      // Revalidate on each load so a new deploy shows up at once; unchanged files answer 304.
      cacheControl: [s3deploy.CacheControl.fromString('no-cache')],
    });
    if (existsSync(webBuild)) {
      new s3deploy.BucketDeployment(this, 'WebFonts', {
        destinationBucket: site,
        sources: [s3deploy.Source.asset(webBuild)],
        exclude: ['*'],
        include: [fonts],
        prune: false,
        memoryLimit: 512,
        cacheControl: [s3deploy.CacheControl.fromString('public, max-age=604800')],
      });
    }

    new CfnOutput(this, 'ClaudeApiKeySecret', { value: claudeKey.secretName });
    new CfnOutput(this, 'WebUrl', { value: `https://${webHost}` });
    new CfnOutput(this, 'CdnDomain', { value: cdn.distributionDomainName });
    new CfnOutput(this, 'ApiUrl', { value: apiUrl });
    new CfnOutput(this, 'UserPoolId', { value: users.userPoolId });
    new CfnOutput(this, 'UserPoolClientId', { value: appClient.userPoolClientId });
    if (authDomain) {
      // auth.saenggak.app gets a CNAME (proxy off) to this address.
      new CfnOutput(this, 'AuthDomainTarget', { value: authDomain.cloudFrontEndpoint });
    }
    new CfnOutput(this, 'DbClusterArn', { value: db.clusterArn });
  }

  /** Google and Apple as sign-in providers, each once its settings are filled in. */
  private socialSignIn(users: cognito.UserPool, s: SignInSettings) {
    const out: { name: string; provider: cognito.UserPoolClientIdentityProvider; idp: cognito.IUserPoolIdentityProvider }[] = [];
    if (s.google.clientId) {
      const idp = new cognito.UserPoolIdentityProviderGoogle(this, 'Google', {
        userPool: users,
        clientId: s.google.clientId,
        clientSecretValue: SecretValue.secretsManager('saenggak/google-client-secret'),
        scopes: ['openid', 'email'],
        attributeMapping: {
          email: cognito.ProviderAttribute.GOOGLE_EMAIL,
          emailVerified: cognito.ProviderAttribute.GOOGLE_EMAIL_VERIFIED,
        },
      });
      out.push({ name: 'google', provider: cognito.UserPoolClientIdentityProvider.GOOGLE, idp });
    }
    if (s.apple.teamId && s.apple.keyId) {
      const idp = new cognito.UserPoolIdentityProviderApple(this, 'Apple', {
        userPool: users,
        clientId: s.apple.servicesId,
        teamId: s.apple.teamId,
        keyId: s.apple.keyId,
        privateKeyValue: SecretValue.secretsManager('saenggak/apple-private-key'),
        scopes: ['email'],
        attributeMapping: {
          email: cognito.ProviderAttribute.APPLE_EMAIL,
          emailVerified: cognito.ProviderAttribute.APPLE_EMAIL_VERIFIED,
        },
      });
      out.push({ name: 'apple', provider: cognito.UserPoolClientIdentityProvider.APPLE, idp });
    }
    return out;
  }

  /**
   * A firewall: Amazon's list of known bad addresses (botnets, scanners),
   * known attack patterns, and a cap on requests per address per five
   * minutes. On CloudFront, writes to the API get a tighter cap.
   */
  private firewall(id: string, scope: 'CLOUDFRONT' | 'REGIONAL', perAddress = 2000): wafv2.CfnWebACL {
    const seen = (name: string) => ({ cloudWatchMetricsEnabled: true, metricName: `${id}${name}`, sampledRequestsEnabled: true });
    const managed = (name: string, priority: number) => ({
      name,
      priority,
      overrideAction: { none: {} },
      statement: { managedRuleGroupStatement: { vendorName: 'AWS', name } },
      visibilityConfig: seen(name),
    });
    const rules: wafv2.CfnWebACL.RuleProperty[] = [
      managed('AWSManagedRulesAmazonIpReputationList', 0),
      managed('AWSManagedRulesKnownBadInputsRuleSet', 1),
      {
        name: 'PerAddress',
        priority: 2,
        action: { block: {} },
        statement: { rateBasedStatement: { limit: perAddress, aggregateKeyType: 'IP' } },
        visibilityConfig: seen('PerAddress'),
      },
    ];
    if (scope === 'CLOUDFRONT') {
      rules.push({
        name: 'ApiWritesPerAddress',
        priority: 3,
        action: { block: {} },
        statement: {
          rateBasedStatement: {
            limit: 300,
            aggregateKeyType: 'IP',
            scopeDownStatement: {
              andStatement: {
                statements: [
                  {
                    byteMatchStatement: {
                      fieldToMatch: { uriPath: {} },
                      positionalConstraint: 'STARTS_WITH',
                      searchString: '/api/',
                      textTransformations: [{ priority: 0, type: 'NONE' }],
                    },
                  },
                  {
                    notStatement: {
                      statement: {
                        byteMatchStatement: {
                          fieldToMatch: { method: {} },
                          positionalConstraint: 'EXACTLY',
                          searchString: 'GET',
                          textTransformations: [{ priority: 0, type: 'NONE' }],
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
        },
        visibilityConfig: seen('ApiWrites'),
      });
    }
    return new wafv2.CfnWebACL(this, id, {
      scope,
      defaultAction: { allow: {} },
      rules,
      visibilityConfig: seen('All'),
    });
  }
}
