#!/usr/bin/env bash
set -eo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

RULES_DIR="$TEST_DIR/rules"
REALM_HEALTH_STATUS_FILE="$TEST_DIR/health_status.conf"
mkdir -p "$RULES_DIR"

# generate_endpoints_from_rules only needs these helpers from the wider application.
reorder_rule_ids() { return 0; }
validate_ip() { return 0; }
get_transport_config() { return 0; }
read_rule_file() {
    unset RULE_ID RULE_NAME RULE_ROLE LISTEN_PORT LISTEN_IP THROUGH_IP REMOTE_HOST REMOTE_PORT
    unset FORWARD_TARGET SECURITY_LEVEL TLS_SERVER_NAME TLS_CERT_PATH TLS_KEY_PATH WS_PATH WS_HOST
    unset ENABLED BALANCE_MODE FAILOVER_ENABLED TARGET_STATES WEIGHTS PROTOCOL
    # shellcheck disable=SC1090
    source "$1"
}

# shellcheck disable=SC1091
source "$PROJECT_DIR/lib/realm.sh"

cat > "$RULES_DIR/rule-1.conf" <<'EOF'
RULE_ID=1
RULE_NAME="primary-backup-test"
RULE_ROLE="1"
LISTEN_PORT="443"
LISTEN_IP="0.0.0.0"
THROUGH_IP="::"
REMOTE_HOST="primary.example,backup.example"
REMOTE_PORT="8443"
SECURITY_LEVEL="standard"
TLS_SERVER_NAME=""
TLS_CERT_PATH=""
TLS_KEY_PATH=""
WS_PATH=""
WS_HOST=""
ENABLED="true"
BALANCE_MODE="primary_backup"
FAILOVER_ENABLED="true"
TARGET_STATES="primary.example:8443,backup.example:8443"
WEIGHTS="1,1"
PROTOCOL="both"
EOF

assert_active_target() {
    local expected="$1"
    local endpoints
    endpoints=$(generate_endpoints_from_rules)
    grep -q "\"remote\": \"$expected\"" <<< "$endpoints"
    ! grep -q 'extra_remotes' <<< "$endpoints"
    ! grep -q '"balance"' <<< "$endpoints"
}

# No state yet: fail open to the configured primary.
: > "$REALM_HEALTH_STATUS_FILE"
assert_active_target "primary.example:8443"

# Primary down: select the first healthy backup.
printf '%s\n' \
    '1|primary.example|failed|2|0|100|100' \
    '1|backup.example|healthy|0|2|100|0' > "$REALM_HEALTH_STATUS_FILE"
assert_active_target "backup.example:8443"

# Primary recovered: deterministic automatic failback.
printf '%s\n' \
    '1|primary.example|healthy|0|2|300|0' \
    '1|backup.example|healthy|0|2|300|0' > "$REALM_HEALTH_STATUS_FILE"
assert_active_target "primary.example:8443"

# All targets down: retain primary rather than emit an invalid empty endpoint.
printf '%s\n' \
    '1|primary.example|failed|2|0|400|400' \
    '1|backup.example|failed|2|0|400|400' > "$REALM_HEALTH_STATUS_FILE"
assert_active_target "primary.example:8443"

echo "primary/backup failover tests passed"
