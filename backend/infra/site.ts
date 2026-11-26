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
