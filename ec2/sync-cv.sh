#!/bin/bash
# Runs as root from user data and systemd. Do not insert AWS access keys here.
set -u
BUCKET="cv-23l-3104"
DEST="/var/www/html"
LOG="/var/log/cv-sync.log"
mkdir -p "$DEST"
fail() { printf '%s status=FAILED reason=%s\n' "$(date -u +%FT%TZ)" "$1" >> "$LOG"; exit 1; }
# --delete keeps the web root synchronized with the three site objects.
aws s3 sync "s3://${BUCKET}/site/" "$DEST/" --delete >/dev/null 2>&1 || fail "s3_sync"
TOKEN=$(curl -fsS --connect-timeout 2 --max-time 6 -X PUT \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
  'http://169.254.169.254/latest/api/token') || fail "imds_token"
INSTANCE_ID=$(curl -fsS --connect-timeout 2 --max-time 6 \
  -H "X-aws-ec2-metadata-token: ${TOKEN}" \
  'http://169.254.169.254/latest/meta-data/instance-id') || fail "instance_id"
[ -s "$DEST/index.html" ] || fail "missing_index"
[ -n "$INSTANCE_ID" ] || fail "empty_instance_id"
# S3 retains the original placeholder. Only the local served copy changes.
sed -i "s/{{HOSTED_ON}}/EC2 ${INSTANCE_ID}/g" "$DEST/index.html" || fail "footer_replacement"
printf '%s status=SUCCESS instance=%s\n' "$(date -u +%FT%TZ)" "$INSTANCE_ID" >> "$LOG"
