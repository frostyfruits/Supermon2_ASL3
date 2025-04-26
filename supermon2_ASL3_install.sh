#!/usr/bin/env bash
#
# install_supermon2_asl3.sh
# One-step Supermon2 V2.0 installer for ASL-3 / Asterisk 20+.
#
# Usage:
#   sudo ./install_supermon2_asl3.sh

set -euo pipefail

# --- CONFIG -------------------------------------------------------------
TMPDIR="/var/tmp/supermon2-install"      # exec-allowed temp dir
TAR_URL="https://crompton.com/hamradio/supermon2/supermon2-V2.0.tar"
ASTDB="/var/lib/asterisk/astdb"
# ------------------------------------------------------------------------

# 1) Must be root
(( EUID == 0 )) || { echo "ERROR: run as root"; exit 1; }

# 2) Detect Apache docroot ? SUPROOT
if [ -d /srv/http ]; then
  SUPROOT="/srv/http/supermon2"
elif [ -d /var/www/html ]; then
  SUPROOT="/var/www/html/supermon2"
else
  echo "ERROR: no /srv/http or /var/www/html present" >&2
  exit 1
fi
echo "? Installing Supermon2 into: $SUPROOT"

# 3) Prep scratch
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

# 4) Download installer
echo "--> Downloading Supermon2 installer to $TMPDIR"
wget -qO "$TMPDIR/supermon2-V2.0.tar" "$TAR_URL"
chmod 750 "$TMPDIR/supermon2-V2.0.tar"

# 5) HamVoIP hack: symlink /srv/http ? /var/www/html if needed
if [ ! -e /srv/http ]; then
  echo "--> Symlinking /srv/http ? /var/www/html"
  mkdir -p /var/www/html
  ln -s /var/www/html /srv/http
fi

# 6) Run the self-extractor **in place** (so $0 resolves correctly)
echo "--> Running Supermon2 installer (answer Y to all prompts)"
pushd "$TMPDIR" >/dev/null
bash ./supermon2-V2.0.tar || { echo "ERROR: installer failed"; exit 1; }
popd >/dev/null

# 7) Verify it unpacked into SUPROOT
if [ ! -d "$SUPROOT/user_files" ]; then
  echo "ERROR: installer did not create $SUPROOT" >&2
  exit 1
fi

# 8) Prompt & update AMI manager secret
read -sp "Enter your Asterisk [admin] manager secret: " MGRPASS
echo
CFG="/etc/asterisk/manager.conf"
cp "$CFG"{,.bak}
awk -v pw="$MGRPASS" '
  /^\[admin\]/ { print; inadmin=1; next }
  /^\[/        { inadmin=0 }
  inadmin && /^secret *=/ { sub(/=.*/, "= " pw); print; next }
  { print }
  END { if (!inadmin) print "[admin]\nsecret = " pw }
' "$CFG" > "$CFG".new && mv "$CFG".new "$CFG"

# 9) Prompt & patch allmon.ini
read -p "Enter your Supermon2 node number: " NODE
INI="$SUPROOT/user_files/allmon.ini"
cp "$INI"{,.bak}
sed -i \
  -e "s/^\[1998\]/[$NODE]/" \
  -e "s/^passwd *=.*/passwd = $MGRPASS/" \
  "$INI"

# 10) Patch AST_DB updater for ASL-3
echo "--> Patching ast_var_update.sh for ASL-3 ASTDB"
UPD=$(find /usr/local/sbin -name ast_var_update.sh -print -quit)
[ -f "$UPD" ] || UPD=$(find "$SUPROOT" -name ast_var_update.sh -print -quit)
cp "$UPD"{,.bak}
sed -i \
  -e "s|/var/lib/asterisk/astdb/|$ASTDB/|g" \
  -e "s|/var/lib/asterisk/\*cdr-csv/|$ASTDB/|g" \
  "$UPD"

# 11) Install cron job for per-minute AST_DB updates
echo "--> Installing cron job for AST_DB updater"
CRONLINE="* * * * * root $UPD"
grep -Fxq "$CRONLINE" /etc/crontab || echo "$CRONLINE" >> /etc/crontab

# 12) Done!
cat <<EOF

? Supermon2 V2.0 installed & patched for ASL-3!

 Web UI:   http://<YOUR_NODE_IP>/supermon2/
 Config:   $INI
 Updater:  $UPD
 Cron:     runs every minute

Next steps:
 1) Secure the UI:
      cd $SUPROOT/user_files && ./set_password.sh
 2) Lock down $SUPROOT (htpasswd or firewall)
 3) Reload Asterisk manager:
      asterisk -rx "manager reload"

Enjoy! ??

EOF
