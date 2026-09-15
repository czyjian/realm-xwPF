#!/usr/bin/env bash
set -eo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
RULES_DIR="$TEST_DIR/rules"
REALM_HEALTH_STATUS_FILE="$TEST_DIR/health_status.conf"
mkdir -p "$RULES_DIR"
source "$PROJECT_DIR/lib/rules.sh"
clear() { return 0; }

write_rule() {
    cat > "$RULES_DIR/rule-1.conf" <<EOF
RULE_ID=1
RULE_NAME="test"
RULE_ROLE="1"
LISTEN_PORT="443"
REMOTE_HOST="primary.example,backup.example"
REMOTE_PORT="8443"
BALANCE_MODE="$1"
WEIGHTS="1,1"
FAILOVER_ENABLED="true"
EOF
}

printf '%s\n' '1|primary.example|healthy|0|2|100|0' \
    '1|backup.example|healthy|0|2|100|0' > "$REALM_HEALTH_STATUS_FILE"

write_rule primary_backup
output=$(load_balance_management_menu <<< '0')
grep -q '\[主节点\]' <<< "$output"
grep -q '\[备用节点\]' <<< "$output"
! grep -q '%' <<< "$output"
! grep -q '权重:' <<< "$output"
grep -q '4\. 配置主备切换' <<< "$output"

# Prompts are printed by read only in interactive use; verify their source range.
grep -q '请输入选择 \[0-4\]' "$PROJECT_DIR/lib/rules.sh"
grep -q '无效选择，请输入 0-4' "$PROJECT_DIR/lib/rules.sh"

# Existing load-balancing percentages remain visible.
write_rule roundrobin
output=$(load_balance_management_menu <<< '0')
grep -q '(50.0%)' <<< "$output"
grep -q '权重: 1' <<< "$output"

# The new menu entry dispatches primary/backup directly, rather than merely
# widening the prompt while leaving option 4 unhandled.
switch_balance_mode() { echo "selected-mode:$1"; }
output=$(load_balance_management_menu <<< $'4\n0')
grep -q 'selected-mode:primary_backup' <<< "$output"
echo "balance menu display tests passed"
