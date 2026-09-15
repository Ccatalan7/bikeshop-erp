#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cd "$DB_ROOT"
expected_staging_ref="bczzjhjrpmtpgwdvlbut"
[[ "${VINABIKE_STAGING_REACTIVATION_CONFIRM:-}" == "$expected_staging_ref" ]] ||
  die "Staging is policy-dormant; explicit owner reactivation is required"

die "This command is retired: core_schema.sql is an incomplete historical/local reference and is never applied to a hosted database. Deploy one reviewed standalone migration through scripts/db/deploy_migration.sh."
