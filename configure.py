#!/usr/bin/env python3
"""Fill in identity and AWS resource-name placeholders in the starter files.

Usage: python configure.py --roll 23l-3104 --name 'Your Full Name' --email you@example.com
       [--bucket cv-23l-3104-1234]
Run only once on a fresh starter copy. It does not access AWS or create resources.
"""
import argparse
from pathlib import Path
import re
import json

parser = argparse.ArgumentParser()
parser.add_argument('--roll', required=True)
parser.add_argument('--name', required=True)
parser.add_argument('--email', required=True)
parser.add_argument('--bucket', default=None)
args = parser.parse_args()
roll = args.roll.lower()
if not re.fullmatch(r'[a-z0-9][a-z0-9-]{2,40}', roll):
    parser.error('--roll must use lowercase letters/numbers/hyphens')
bucket = args.bucket or f'cv-{roll}'
if not re.fullmatch(r'[a-z0-9][a-z0-9-]{2,61}[a-z0-9]', bucket):
    parser.error('Invalid bucket name; use lowercase letters, digits and hyphens')
if '@' not in args.email:
    parser.error('--email must be a valid-looking email address')
replacement = {
    '__ROLL__': roll,
    '__FULLNAME__': args.name,
    '__EMAIL__': args.email,
    '__BUCKET__': bucket,
    '__FUNCTION__': f'cv-func-{roll}',
    '__EC2_ROLE__': f'cv-ec2-role-{roll}',
    '__LAMBDA_ROLE__': f'cv-lambda-role-{roll}',
    '__EC2_POLICY_NAME__': f'cv-ec2-read-{roll}',
    '__LAMBDA_POLICY_NAME__': f'cv-lambda-read-{roll}',
}
root = Path(__file__).resolve().parent
paths = [root / 'site/index.html', root / 'ec2/sync-cv.sh',
         root / 'ec2/user-data.sh', *sorted((root / 'iam').glob('*.json')),
         root / 'collect-evidence.sh', root / 'README.md']
for path in paths:
    content = path.read_text(encoding='utf-8')
    for key, value in replacement.items():
        content = content.replace(key, value)
    path.write_text(content, encoding='utf-8')
for policy_path in (root / 'iam').glob('*.json'):
    json.loads(policy_path.read_text(encoding='utf-8'))
print(f'Configured roll={roll}, bucket={bucket}')
print('NEXT: Replace site/cv.pdf with YOUR CV and edit Education/Skills/Projects in site/index.html.')
print('Then upload ONLY site/index.html, site/style.css, site/cv.pdf to S3.')
