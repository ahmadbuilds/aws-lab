#!/bin/bash
set -euxo pipefail
# Amazon Linux 2023. Runs once on first boot via cloud-init.
dnf -y install httpd
systemctl enable --now httpd
cat > /usr/local/bin/sync-cv.sh <<'SYNC_SCRIPT_END'
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
SYNC_SCRIPT_END
chmod 755 /usr/local/bin/sync-cv.sh
cat > /etc/systemd/system/cv-sync.service <<'UNIT_END'
[Unit]
Description=Synchronize private S3 CV to Apache web root
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
UNIT_END
cat > /etc/systemd/system/cv-sync.timer <<'TIMER_END'
[Unit]
Description=Refresh CV site from S3 every two minutes
[Timer]
OnBootSec=2min
OnUnitInactiveSec=2min
Persistent=true
Unit=cv-sync.service
[Install]
WantedBy=timers.target
TIMER_END
systemctl daemon-reload
# Start the timer before the first fetch so temporary IAM/S3 propagation
# issues do not permanently prevent future synchronization.
systemctl enable --now cv-sync.timer
/usr/local/bin/sync-cv.sh || echo 'Initial sync failed; timer will retry.'
