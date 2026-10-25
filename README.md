# AWS CV Hosting Lab — 23l-3104

**Student:** Muhammad Ahmed  
**Roll number:** 23l-3104  
**Email:** l233104@lhr.nu.edu.pk  
**Bucket:** `cv-23l-3104`  
**EC2 site:** `http://13.53.193.216/`  
**Lambda site:** `https://k4luekpkuegdezsphqz6iuua2u0niaza.lambda-url.eu-north-1.on.aws/`

## Architecture

```
Visitor --HTTP:80--> EC2 (Apache) <---sync each 2 min--- IAM role ---> private S3 site/
Visitor --HTTPS----> Lambda Function URL <--GetObject----- IAM role ---> private S3 site/

Direct anonymous S3 GET --------------------------------------> 403 AccessDenied
```

On the EC2 path, the visitor reaches Apache at the instance's public IPv4; Apache serves its local copy of S3 content, refreshed by a systemd timer. On the Lambda path, the Function URL invokes Python, which reads the private S3 object using its execution role and returns a path-specific HTTP response.

## Security and permissions

The EC2 role `cv-ec2-role-23l-3104` allows `s3:GetObject` only for objects under the `site/` prefix and `s3:ListBucket` with the prefix condition `site/`. The Lambda role `cv-lambda-role-23l-3104` allows `s3:GetObject` under the same prefix, with no `s3:ListBucket` permission, and uses the managed `AWSLambdaBasicExecutionRole` policy for CloudWatch logging. Neither application uses hardcoded AWS access keys.

## Denied write test

Executed on the EC2 instance using SSH from Windows PowerShell:

```bash
aws s3 cp /etc/hosts s3://cv-23l-3104/site/style.css
```

```text
[ec2-user@ip-172-31-39-150 ~]$ aws s3 cp /etc/hosts s3://cv-23l-3104/site/style.css
upload failed: ../../etc/hosts to s3://cv-23l-3104/site/style.css An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::279809866675:assumed-role/cv-ec2-role-23l-3104/i-060c9b2c1a024a525 is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3104/site/style.css" because no identity-based policy allows the s3:PutObject action
```

## Last 10 sync log lines

```bash
sudo tail -n 10 /var/log/cv-sync.log
```

```text
[ec2-user@ip-172-31-39-150 ~]$ sudo tail -n 10 /var/log/cv-sync.log
2026-10-25T17:51:55Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T17:54:05Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T17:56:15Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T17:58:25Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T18:00:35Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T18:02:44Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T18:04:46Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T18:06:56Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T18:09:05Z status=SUCCESS instance=i-060c9b2c1a024a525
2026-10-25T18:11:06Z status=SUCCESS instance=i-060c9b2c1a024a525
```

## Five written answers

1. **Why IAM roles instead of access keys?** An IAM role supplies short-lived credentials to the EC2 and Lambda services without embedding long-lived secrets. An access key inside user data could be exposed to anyone who can inspect the instance configuration and then abused to access AWS resources.
2. **Opening the S3 URL directly?** An anonymous visitor receives an AccessDenied response, normally HTTP 403. S3 Block Public Access is enabled and the bucket has no policy granting public access; the service roles are the only readers.
3. **Why is the Lambda URL public but S3 private?** The Lambda resource-based policy permits unauthenticated invocation through its Function URL using `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction`. That makes the CV publicly viewable through controlled application code, while the original bucket contents remain accessible only to the two role principals.
4. **Cost at idle and with 100x traffic?** EC2 can charge for the running server and public IPv4/EBS even while idle, subject to account Free Tier eligibility, while Lambda compute billing generally tracks requests and execution (S3, logs, and storage can still incur charges). A 100x traffic increase may overload the small EC2 instance, while Lambda scales with requests but may incur more usage charges and can hit concurrency/service limits.
5. **What is lost after deleting EC2?** The public EC2 endpoint, its web server, local synchronized files, and local sync logs disappear (unless separately preserved). The private S3 CV files, IAM roles, and Lambda website remain if not deleted.

## Sources and adaptations

- The initial lab starter structure and implementation examples (EC2 user data and sync script, Lambda handler, IAM policies, and evidence collector) were prepared with ChatGPT assistance and adapted for this AWS deployment. The commands and outputs above reflect tests performed on the deployed AWS resources.
- AWS documentation referenced for the setup: [EC2 user data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) and [Lambda Function URL authentication](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html).

## Submission files

The files to include in the public GitHub repository are `README.md`, `collect-evidence.sh`, `evidence.txt`, `site/index.html`, `site/style.css`, `site/cv.pdf`, `ec2/user-data.sh`, `ec2/sync-cv.sh`, the Lambda function code in `lambda/`, and the IAM trust and permission policies in `iam/`. Private keys and AWS access credentials must not be committed.
