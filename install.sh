#!/bin/bash
set -euo pipefail
if [[ $(id -u) -ne 0 ]]; then echo 'Run this installer as root.' >&2; exit 1; fi
if [[ ! -f /etc/debian_version ]]; then echo 'Debian/Ubuntu is required.' >&2; exit 1; fi
apt-get update
apt-get install -y ca-certificates curl git gnupg util-linux udev smartmontools samba nfs-kernel-server e2fsprogs btrfs-progs openssl python3
if ! command -v node >/dev/null || [[ $(node -p 'Number(process.versions.node.split(".")[0])') -lt 22 ]]; then
 install -d -m 0755 /etc/apt/keyrings
 curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
 echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' > /etc/apt/sources.list.d/nodesource.list
 apt-get update
 apt-get install -y nodejs
fi
command -v npm >/dev/null || apt-get install -y npm
node -e 'if(Number(process.versions.node.split(".")[0])<22)process.exit(1)'
getent group lightnas >/dev/null || groupadd --system lightnas
id lightnas >/dev/null 2>&1 || useradd --system --gid lightnas --home-dir /var/lib/lightnas --shell /usr/sbin/nologin lightnas
if [[ -d /opt/lightnas/.git ]]; then
 [[ -z $(git -C /opt/lightnas status --porcelain) ]] || { echo 'Installation has local changes; update aborted.' >&2; exit 1; }
 git -C /opt/lightnas pull --ff-only
elif [[ -e /opt/lightnas ]]; then
 echo '/opt/lightnas exists without a Git checkout; refusing to replace it.' >&2; exit 1
else
 git clone https://github.com/Cyverax/LightNAS.git /opt/lightnas
fi
cd /opt/lightnas
npm test
chown -R root:root /opt/lightnas
chmod -R go-w /opt/lightnas
install -d -m 0750 -o root -g lightnas /etc/lightnas
if [[ ! -f /etc/lightnas/agent.token ]]; then openssl rand -hex 32 > /etc/lightnas/agent.token; fi
chown root:lightnas /etc/lightnas/agent.token
chmod 0640 /etc/lightnas/agent.token
install -d -m 0700 /var/lib/lightnas-storage
install -d -m 0755 /etc/exports.d /srv/lightnas
for file in /etc/samba/lightnas-shares.conf /etc/exports.d/lightnas.exports; do
 if [[ ! -e "$file" ]]; then install -m 0600 /dev/null "$file"; fi
done
# Insert the include inside the existing global section without replacing host config.
python3 - <<'PY'
from pathlib import Path
import re,shutil
p=Path('/etc/samba/smb.conf');s=p.read_text()
if not re.search(r'^\s*include\s*=\s*/etc/samba/lightnas-shares.conf\s*$',s,re.M|re.I):
 m=re.search(r'^\s*\[global\]\s*$',s,re.M|re.I)
 if not m: raise SystemExit('Samba global section missing; configure the include manually.')
 shutil.copy2(p,str(p)+'.lightnas-backup')
 s=s[:m.end()]+'\n    include = /etc/samba/lightnas-shares.conf'+s[m.end():]
 p.write_text(s)
PY
testparm --suppress-prompt /etc/samba/smb.conf
install -m 0644 deploy/lightnas-storage.service /etc/systemd/system/lightnas-storage.service
install -m 0644 deploy/lightnas.service /etc/systemd/system/lightnas.service
systemctl daemon-reload
systemctl enable --now smbd nfs-kernel-server
systemctl enable lightnas-storage lightnas
systemctl restart lightnas-storage lightnas
systemctl is-active --quiet lightnas-storage lightnas
printf '%s\n' 'LightNAS storage console: http://127.0.0.1:3080' 'Use TLS termination or an SSH tunnel for remote access.' 'Read the administrator token locally from /etc/lightnas/agent.token.' 'Disk initialization remains disabled; enable it only in the root agent service policy.'
