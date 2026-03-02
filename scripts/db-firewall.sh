#!/usr/bin/env bash
#
# Manage RDS security group ingress for direct PostgreSQL access
#
# Usage:
#   ./scripts/db-firewall.sh open     # Allow your current IP
#   ./scripts/db-firewall.sh close    # Revoke your current IP
#   ./scripts/db-firewall.sh list     # Show whitelisted IPs
#
# Prerequisites:
#   - AWS CLI configured with book_vault profile
#

set -euo pipefail

AWS_PROFILE="book_vault"
AWS_REGION="us-east-1"
RDS_SG_NAME="book-vault-rds-sg"
PORT=5432

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_sg_id() {
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${RDS_SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null)

    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
        log_error "Could not find security group '${RDS_SG_NAME}'"
        exit 1
    fi
    echo "$sg_id"
}

get_my_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://checkip.amazonaws.com)
    if [[ -z "$ip" ]]; then
        log_error "Could not determine your public IP address"
        exit 1
    fi
    echo "$ip"
}

cmd_open() {
    local sg_id ip
    sg_id=$(get_sg_id)
    ip=$(get_my_ip)
    local cidr="${ip}/32"

    # Check if already whitelisted
    local existing
    existing=$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=${sg_id}" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[?!IsEgress && FromPort==\`${PORT}\` && CidrIpv4==\`${cidr}\`].SecurityGroupRuleId" \
        --output text 2>/dev/null)

    if [[ -n "$existing" && "$existing" != "None" ]]; then
        log_warn "Your IP (${ip}) is already whitelisted"
        return 0
    fi

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port "$PORT" \
        --cidr "$cidr" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        > /dev/null

    log_info "Opened port ${PORT} for ${CYAN}${ip}${NC}"
    echo ""
    echo -e "  Connect with: ${CYAN}psql \$(aws secretsmanager get-secret-value --secret-id book-vault/database --profile ${AWS_PROFILE} --region ${AWS_REGION} --query 'SecretString' --output text | node -e \"process.stdin.on('data',d=>console.log(JSON.parse(d).DATABASE_URL))\")${NC}"
    echo ""
    log_warn "Remember to close when done: npm run db:firewall:close"
}

cmd_close() {
    local sg_id ip
    sg_id=$(get_sg_id)
    ip=$(get_my_ip)
    local cidr="${ip}/32"

    aws ec2 revoke-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port "$PORT" \
        --cidr "$cidr" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        > /dev/null 2>&1 || true

    log_info "Closed port ${PORT} for ${CYAN}${ip}${NC}"
}

cmd_list() {
    local sg_id
    sg_id=$(get_sg_id)

    echo -e "${GREEN}Whitelisted IPs for RDS (port ${PORT}):${NC}"
    echo ""

    local rules
    rules=$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=${sg_id}" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[?!IsEgress && FromPort==\`${PORT}\`].[CidrIpv4,ReferencedGroupInfo.GroupId,Description]" \
        --output text 2>/dev/null)

    if [[ -z "$rules" ]]; then
        echo "  (none)"
        return 0
    fi

    local my_ip
    my_ip=$(get_my_ip)

    while IFS=$'\t' read -r cidr sg_ref description; do
        if [[ -n "$sg_ref" && "$sg_ref" != "None" ]]; then
            echo -e "  ${CYAN}Security Group${NC}  ${sg_ref}  (ECS tasks)"
        elif [[ -n "$cidr" && "$cidr" != "None" ]]; then
            local label=""
            if [[ "$cidr" == "${my_ip}/32" ]]; then
                label="  ${YELLOW}← you${NC}"
            fi
            echo -e "  ${CYAN}${cidr}${NC}${label}"
        fi
    done <<< "$rules"

    echo ""
}

# Main
case "${1:-}" in
    open)  cmd_open ;;
    close) cmd_close ;;
    list)  cmd_list ;;
    *)
        echo "Usage: $0 {open|close|list}"
        echo ""
        echo "  open   Allow your current public IP to connect to RDS"
        echo "  close  Revoke your current public IP"
        echo "  list   Show all whitelisted IPs"
        exit 1
        ;;
esac
