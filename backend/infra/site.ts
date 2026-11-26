/**
 * The site's own address. Until [certificateArn] is set, the site and the API
 * answer only at the CloudFront address.
 *
 * The certificate is made by hand in ACM in us-east-1 (CloudFront only takes
 * certificates from there) for the domain and www, validated with the DNS
 * records ACM shows, which go into Cloudflare's DNS with the proxy off.
 */
export const SITE = {
  domain: 'saenggak.app',
  certificateArn: 'arn:aws:acm:us-east-1:242126391246:certificate/68b0882d-5bda-442d-bd42-ae9d03a54c75',
};

/**
 * Sign-in with Google and Apple, through Cognito's sign-in pages at [authDomain].
 *
 * Nothing here is secret. The secrets live in AWS Secrets Manager (us-east-1),
 * as plain text, under the names below:
 * - Google's client secret: `saenggak/google-client-secret`
 * - Apple's private key (the whole .p8 file): `saenggak/apple-private-key`
 *
 * Each part turns on when its fields are filled in: the domain once its
 * us-east-1 certificate is issued, Google once its client id is set, Apple once
 * its team id and key id are set.
 */
export const SIGN_IN = {
  authDomain: 'auth.saenggak.app',
  authCertificateArn: 'arn:aws:acm:us-east-1:242126391246:certificate/0e5b06f6-60a2-44b9-bdfa-6b99abaf9c60',
  google: { clientId: '579952219461-f4tcp0s3httvr7nca1i39v3j5kmrga0t.apps.googleusercontent.com' },
  apple: { servicesId: 'app.saenggak.signin', teamId: '', keyId: '' },
};

export type SignInSettings = typeof SIGN_IN;
