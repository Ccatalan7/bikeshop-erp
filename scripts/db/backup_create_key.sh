#!/usr/bin/env bash
# Creates the key pair of the production database backup, once.
#
# The public certificate is committed at scripts/db/backup/recipient.pem: the
# backup job encrypts every dump to it, so GitHub holds the database password
# but never anything that opens a backup. The private key goes only to the
# macOS Keychain of the Mac that runs this, base64 in one line (Keychain hands
# multi-line values back as hex). It is never printed and never overwritten:
# losing it makes every backup unreadable, so the owner keeps a copy outside
# this Mac (docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly BACKUP_KEY_SERVICE="Vinabike ERP respaldo de la base v1"
readonly BACKUP_CERT="$DB_ROOT/scripts/db/backup/recipient.pem"

require_command openssl
require_command security

if security find-generic-password -s "$BACKUP_KEY_SERVICE" -a "$USER" >/dev/null 2>&1; then
  die "The Keychain already holds '$BACKUP_KEY_SERVICE'; refusing to replace the key that opens the existing backups"
fi
[[ ! -e "$BACKUP_CERT" ]] || die "$BACKUP_CERT exists; it belongs to the key already in use"

work="$(mktemp -d)"
trap 'rm -f "$work/key.pem" "$work/cert.pem"; rmdir "$work" 2>/dev/null || true' EXIT
chmod 700 "$work"

openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 36500 \
  -subj "/CN=Vinabike respaldo de la base" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

security add-generic-password -s "$BACKUP_KEY_SERVICE" -a "$USER" \
  -l "$BACKUP_KEY_SERVICE" -w "$(base64 <"$work/key.pem" | tr -d '\n')"

mkdir -p "$(dirname "$BACKUP_CERT")"
cp "$work/cert.pem" "$BACKUP_CERT"

echo "Private key stored in the Keychain as '$BACKUP_KEY_SERVICE'."
echo "Public certificate: ${BACKUP_CERT#"$DB_ROOT/"} (sha256 $(sha256_file "$BACKUP_CERT"))"
