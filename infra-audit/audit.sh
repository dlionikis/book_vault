#!/usr/bin/env bash
#
# AWS Infrastructure Audit Script
# Book Vault Production Environment
#
# Usage: ./audit.sh [options]
#
# This script discovers and documents AWS infrastructure using read-only API calls.
# All outputs are saved to out/ and docs/infra/
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/out"
RAW_DIR="${OUT_DIR}/raw"
DOCS_DIR="${SCRIPT_DIR}/../docs/infra"
LIB_DIR="${SCRIPT_DIR}/lib"

AUDIT_VERSION="1.0.0"
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Default region (can be overridden)
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
DRY_RUN=false
SKIP_DIAGRAM=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "[DEBUG] $1"
    fi
}

show_help() {
    cat << EOF
AWS Infrastructure Audit Script - Book Vault

Usage: ./audit.sh [options]

Options:
    --region REGION     Override AWS region (default: $REGION)
    --dry-run           Validate setup without running audit
    --skip-diagram      Skip Graphviz rendering
    --verbose, -v       Enable verbose output
    --help, -h          Show this help message

Examples:
    ./audit.sh                      # Full audit with default region
    ./audit.sh --region us-west-2   # Override region
    ./audit.sh --dry-run            # Validate setup only

Environment Variables:
    AWS_REGION          Default region for AWS CLI
    AWS_PROFILE         AWS profile to use
    AWS_ACCESS_KEY_ID   Access key (if not using profile)
    AWS_SECRET_ACCESS_KEY Secret key (if not using profile)

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-diagram)
                SKIP_DIAGRAM=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing+=("aws (AWS CLI v2)")
    else
        local aws_version=$(aws --version 2>&1 | head -1)
        log_debug "AWS CLI: $aws_version"
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        missing+=("jq (brew install jq)")
    else
        log_debug "jq: $(jq --version)"
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    else
        log_debug "Python: $(python3 --version)"
    fi

    # Check Graphviz (optional)
    if ! command -v dot &> /dev/null; then
        log_warn "Graphviz not found - diagram will not be rendered"
        log_warn "Install with: brew install graphviz"
        SKIP_DIAGRAM=true
    else
        log_debug "Graphviz: $(dot -V 2>&1)"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools:"
        for tool in "${missing[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi

    log_success "All prerequisites met"
}

# Validate AWS credentials
check_aws_auth() {
    log_info "Validating AWS credentials..."

    if ! aws sts get-caller-identity --output json > "${RAW_DIR}/caller-identity.json" 2>&1; then
        log_error "AWS authentication failed. Configure credentials and try again."
        cat "${RAW_DIR}/caller-identity.json"
        exit 1
    fi

    ACCOUNT_ID=$(jq -r '.Account' "${RAW_DIR}/caller-identity.json")
    CALLER_ARN=$(jq -r '.Arn' "${RAW_DIR}/caller-identity.json")

    log_success "Authenticated as: $CALLER_ARN"
    log_info "Account ID: $ACCOUNT_ID"
    log_info "Region: $REGION"
}

# =============================================================================
# AWS Discovery Functions
# =============================================================================

# Generic function to run AWS command and save output
# Args: $1 = output filename, $2... = aws command
aws_query() {
    local output_file="$1"
    shift
    local cmd="$@"

    log_debug "Running: aws $cmd"

    if aws $cmd --region "$REGION" --output json > "${RAW_DIR}/${output_file}" 2>&1; then
        log_success "Fetched: $output_file"
        return 0
    else
        local error=$(cat "${RAW_DIR}/${output_file}")
        if [[ "$error" == *"AccessDenied"* ]] || [[ "$error" == *"UnauthorizedAccess"* ]]; then
            log_warn "Permission denied: $output_file"
            echo "{\"error\": \"AccessDenied\", \"command\": \"aws $cmd\"}" > "${RAW_DIR}/${output_file}"
            echo "{\"command\": \"aws $cmd\", \"error\": \"$error\"}" >> "${OUT_DIR}/gaps.jsonl"
        else
            log_warn "Failed: $output_file - $error"
            echo "{\"error\": \"$error\", \"command\": \"aws $cmd\"}" > "${RAW_DIR}/${output_file}"
        fi
        return 1
    fi
}

# Discover VPCs and networking
discover_networking() {
    log_info "Discovering networking resources..."

    aws_query "vpcs.json" ec2 describe-vpcs || true
    aws_query "subnets.json" ec2 describe-subnets || true
    aws_query "route-tables.json" ec2 describe-route-tables || true
    aws_query "internet-gateways.json" ec2 describe-internet-gateways || true
    aws_query "nat-gateways.json" ec2 describe-nat-gateways || true
    aws_query "vpc-endpoints.json" ec2 describe-vpc-endpoints || true
    aws_query "security-groups.json" ec2 describe-security-groups || true
    aws_query "network-acls.json" ec2 describe-network-acls || true

    # Load Balancers
    aws_query "load-balancers.json" elbv2 describe-load-balancers || true

    # If we have load balancers, get listeners and target groups
    if [[ -f "${RAW_DIR}/load-balancers.json" ]] && jq -e '.LoadBalancers | length > 0' "${RAW_DIR}/load-balancers.json" > /dev/null 2>&1; then
        # Get all target groups
        aws_query "target-groups.json" elbv2 describe-target-groups || true

        # Get listeners for each load balancer
        local lb_arns=$(jq -r '.LoadBalancers[].LoadBalancerArn' "${RAW_DIR}/load-balancers.json" 2>/dev/null || echo "")
        local listener_data="[]"

        for arn in $lb_arns; do
            if [[ -n "$arn" ]]; then
                local lb_name=$(echo "$arn" | grep -oE '[^/]+$' || echo "unknown")
                if aws elbv2 describe-listeners --load-balancer-arn "$arn" --region "$REGION" --output json > "${RAW_DIR}/listeners-${lb_name}.json" 2>&1; then
                    listener_data=$(echo "$listener_data" | jq --slurpfile new "${RAW_DIR}/listeners-${lb_name}.json" '. + ($new[0].Listeners // [])')
                fi
            fi
        done
        echo "{\"Listeners\": $listener_data}" > "${RAW_DIR}/all-listeners.json"

        # Get target health for each target group
        local tg_arns=$(jq -r '.TargetGroups[].TargetGroupArn' "${RAW_DIR}/target-groups.json" 2>/dev/null || echo "")
        local target_health="[]"

        for arn in $tg_arns; do
            if [[ -n "$arn" ]]; then
                local tg_name=$(echo "$arn" | grep -oE '[^/]+$' || echo "unknown")
                if aws elbv2 describe-target-health --target-group-arn "$arn" --region "$REGION" --output json > "${RAW_DIR}/target-health-${tg_name}.json" 2>&1; then
                    local health=$(jq --arg arn "$arn" '{TargetGroupArn: $arn, Targets: .TargetHealthDescriptions}' "${RAW_DIR}/target-health-${tg_name}.json")
                    target_health=$(echo "$target_health" | jq --argjson h "$health" '. + [$h]')
                fi
            fi
        done
        echo "{\"TargetHealth\": $target_health}" > "${RAW_DIR}/all-target-health.json"
    fi
}

# Discover compute resources
discover_compute() {
    log_info "Discovering compute resources..."

    # EC2
    aws_query "ec2-instances.json" ec2 describe-instances || true
    aws_query "auto-scaling-groups.json" autoscaling describe-auto-scaling-groups || true
    aws_query "launch-templates.json" ec2 describe-launch-templates || true

    # ECS
    aws_query "ecs-clusters.json" ecs list-clusters || true

    if [[ -f "${RAW_DIR}/ecs-clusters.json" ]] && jq -e '.clusterArns | length > 0' "${RAW_DIR}/ecs-clusters.json" > /dev/null 2>&1; then
        local cluster_arns=$(jq -r '.clusterArns[]' "${RAW_DIR}/ecs-clusters.json" 2>/dev/null || echo "")

        if [[ -n "$cluster_arns" ]]; then
            # Describe clusters
            aws_query "ecs-cluster-details.json" ecs describe-clusters --clusters $cluster_arns --include ATTACHMENTS SETTINGS CONFIGURATIONS STATISTICS || true

            # Get services for each cluster
            for arn in $cluster_arns; do
                local cluster_name=$(echo "$arn" | grep -oE '[^/]+$' || echo "unknown")
                aws_query "ecs-services-${cluster_name}.json" ecs list-services --cluster "$arn" || true

                # Get service details if we have services
                if [[ -f "${RAW_DIR}/ecs-services-${cluster_name}.json" ]] && jq -e '.serviceArns | length > 0' "${RAW_DIR}/ecs-services-${cluster_name}.json" > /dev/null 2>&1; then
                    local service_arns=$(jq -r '.serviceArns[]' "${RAW_DIR}/ecs-services-${cluster_name}.json")
                    aws_query "ecs-service-details-${cluster_name}.json" ecs describe-services --cluster "$arn" --services $service_arns || true
                fi

                # Get task definitions
                aws_query "ecs-tasks-${cluster_name}.json" ecs list-tasks --cluster "$arn" || true

                if [[ -f "${RAW_DIR}/ecs-tasks-${cluster_name}.json" ]] && jq -e '.taskArns | length > 0' "${RAW_DIR}/ecs-tasks-${cluster_name}.json" > /dev/null 2>&1; then
                    local task_arns=$(jq -r '.taskArns[]' "${RAW_DIR}/ecs-tasks-${cluster_name}.json")
                    aws_query "ecs-task-details-${cluster_name}.json" ecs describe-tasks --cluster "$arn" --tasks $task_arns || true
                fi
            done
        fi
    fi

    # ECR
    aws_query "ecr-repositories.json" ecr describe-repositories || true

    # EKS (if present)
    aws_query "eks-clusters.json" eks list-clusters || true

    # Lambda
    aws_query "lambda-functions.json" lambda list-functions || true

    # Lambda function details (environment, role, policy)
    if [[ -f "${RAW_DIR}/lambda-functions.json" ]] && \
       jq -e '.Functions | length > 0' "${RAW_DIR}/lambda-functions.json" > /dev/null 2>&1; then
        local func_names=$(jq -r '.Functions[].FunctionName' "${RAW_DIR}/lambda-functions.json" 2>/dev/null || echo "")
        for func in $func_names; do
            aws_query "lambda-detail-${func}.json" lambda get-function --function-name "$func" || true
            aws_query "lambda-policy-${func}.json" lambda get-policy --function-name "$func" || true
        done
    fi
}

# Discover data stores
discover_data() {
    log_info "Discovering data stores..."

    # RDS
    aws_query "rds-instances.json" rds describe-db-instances || true
    aws_query "rds-clusters.json" rds describe-db-clusters || true
    aws_query "rds-subnet-groups.json" rds describe-db-subnet-groups || true

    # ElastiCache
    aws_query "elasticache-clusters.json" elasticache describe-cache-clusters || true

    # S3 (global, then get details per bucket)
    aws_query "s3-buckets.json" s3api list-buckets || true

    if [[ -f "${RAW_DIR}/s3-buckets.json" ]] && jq -e '.Buckets | length > 0' "${RAW_DIR}/s3-buckets.json" > /dev/null 2>&1; then
        local buckets=$(jq -r '.Buckets[].Name' "${RAW_DIR}/s3-buckets.json" 2>/dev/null || echo "")
        local bucket_details="[]"

        for bucket in $buckets; do
            if [[ -n "$bucket" ]]; then
                log_debug "Getting details for bucket: $bucket"

                # Get bucket location
                local location=""
                if aws s3api get-bucket-location --bucket "$bucket" --output json > "${RAW_DIR}/s3-location-${bucket}.json" 2>&1; then
                    location=$(jq -r '.LocationConstraint // "us-east-1"' "${RAW_DIR}/s3-location-${bucket}.json")
                fi

                # Get bucket policy (may fail if no policy)
                local policy="{}"
                aws s3api get-bucket-policy --bucket "$bucket" --output json > "${RAW_DIR}/s3-policy-${bucket}.json" 2>&1 || true
                if [[ -f "${RAW_DIR}/s3-policy-${bucket}.json" ]] && ! grep -q "error" "${RAW_DIR}/s3-policy-${bucket}.json"; then
                    policy=$(cat "${RAW_DIR}/s3-policy-${bucket}.json")
                fi

                # Get bucket tags
                local tags="[]"
                if aws s3api get-bucket-tagging --bucket "$bucket" --output json > "${RAW_DIR}/s3-tags-${bucket}.json" 2>&1; then
                    tags=$(jq '.TagSet // []' "${RAW_DIR}/s3-tags-${bucket}.json")
                fi

                # Aggregate
                bucket_details=$(echo "$bucket_details" | jq --arg name "$bucket" --arg loc "$location" --argjson tags "$tags" \
                    '. + [{Name: $name, Location: $loc, Tags: $tags}]')
            fi
        done
        echo "{\"BucketDetails\": $bucket_details}" > "${RAW_DIR}/s3-bucket-details.json"
    fi
}

# Discover edge/DNS resources
discover_edge() {
    log_info "Discovering edge and DNS resources..."

    # Route53 (global service, no region needed)
    aws_query "route53-zones.json" route53 list-hosted-zones || true

    if [[ -f "${RAW_DIR}/route53-zones.json" ]] && jq -e '.HostedZones | length > 0' "${RAW_DIR}/route53-zones.json" > /dev/null 2>&1; then
        local zone_ids=$(jq -r '.HostedZones[].Id' "${RAW_DIR}/route53-zones.json" 2>/dev/null | sed 's|/hostedzone/||g' || echo "")

        for zone_id in $zone_ids; do
            if [[ -n "$zone_id" ]]; then
                aws_query "route53-records-${zone_id}.json" route53 list-resource-record-sets --hosted-zone-id "$zone_id" || true
            fi
        done
    fi

    # ACM certificates
    aws_query "acm-certificates.json" acm list-certificates || true

    if [[ -f "${RAW_DIR}/acm-certificates.json" ]] && jq -e '.CertificateSummaryList | length > 0' "${RAW_DIR}/acm-certificates.json" > /dev/null 2>&1; then
        local cert_arns=$(jq -r '.CertificateSummaryList[].CertificateArn' "${RAW_DIR}/acm-certificates.json" 2>/dev/null || echo "")
        local cert_details="[]"

        for arn in $cert_arns; do
            if [[ -n "$arn" ]]; then
                if aws acm describe-certificate --certificate-arn "$arn" --region "$REGION" --output json > "${RAW_DIR}/acm-cert-detail-tmp.json" 2>&1; then
                    cert_details=$(echo "$cert_details" | jq --slurpfile cert "${RAW_DIR}/acm-cert-detail-tmp.json" '. + [$cert[0].Certificate]')
                fi
            fi
        done
        echo "{\"Certificates\": $cert_details}" > "${RAW_DIR}/acm-certificate-details.json"
        rm -f "${RAW_DIR}/acm-cert-detail-tmp.json"
    fi

    # CloudFront (global service)
    aws_query "cloudfront-distributions.json" cloudfront list-distributions || true
}

# Discover security resources
discover_security() {
    log_info "Discovering security resources..."

    # Secrets Manager (names only, never values)
    aws_query "secrets.json" secretsmanager list-secrets || true

    # SSM Parameters (names only, never values)
    aws_query "ssm-parameters.json" ssm describe-parameters || true

    # IAM roles (get roles used by our compute)
    # We'll extract role names from ECS task definitions and EC2 instance profiles later
    aws_query "iam-roles.json" iam list-roles || true
    aws_query "iam-instance-profiles.json" iam list-instance-profiles || true
}

# Discover observability resources
discover_observability() {
    log_info "Discovering observability resources..."

    # CloudWatch Log Groups
    aws_query "log-groups.json" logs describe-log-groups || true

    # CloudWatch Alarms
    aws_query "alarms.json" cloudwatch describe-alarms || true

    # EventBridge Rules
    aws_query "event-rules.json" events list-rules || true

    # EventBridge rule targets
    if [[ -f "${RAW_DIR}/event-rules.json" ]] && \
       jq -e '.Rules | length > 0' "${RAW_DIR}/event-rules.json" > /dev/null 2>&1; then
        local rule_names=$(jq -r '.Rules[].Name' "${RAW_DIR}/event-rules.json" 2>/dev/null || echo "")
        for rule in $rule_names; do
            aws_query "event-targets-${rule}.json" events list-targets-by-rule --rule "$rule" || true
        done
    fi

    # SQS Queues
    aws_query "sqs-queues.json" sqs list-queues || true

    # SNS Topics
    aws_query "sns-topics.json" sns list-topics || true

    # SNS topic subscriptions
    if [[ -f "${RAW_DIR}/sns-topics.json" ]] && \
       jq -e '.Topics | length > 0' "${RAW_DIR}/sns-topics.json" > /dev/null 2>&1; then
        local topic_arns=$(jq -r '.Topics[].TopicArn' "${RAW_DIR}/sns-topics.json" 2>/dev/null || echo "")
        for arn in $topic_arns; do
            local topic_name=$(echo "$arn" | grep -oE '[^:]+$')
            aws_query "sns-subscriptions-${topic_name}.json" sns list-subscriptions-by-topic --topic-arn "$arn" || true
        done
    fi
}

# =============================================================================
# Post-processing
# =============================================================================

normalize_data() {
    log_info "Normalizing data..."

    python3 "${LIB_DIR}/normalize.py" \
        --raw-dir "${RAW_DIR}" \
        --output "${OUT_DIR}/summary.json" \
        --account-id "${ACCOUNT_ID}" \
        --region "${REGION}" \
        --generated-at "${GENERATED_AT}" \
        --version "${AUDIT_VERSION}"

    log_success "Created: out/summary.json"
}

generate_outputs() {
    log_info "Generating documentation and diagram..."

    python3 "${LIB_DIR}/generate.py" \
        --summary "${OUT_DIR}/summary.json" \
        --docs-dir "${DOCS_DIR}" \
        --skip-diagram "${SKIP_DIAGRAM}"

    log_success "Created: docs/infra/production.md"
    log_success "Created: docs/infra/production.dot"

    if [[ "$SKIP_DIAGRAM" != "true" ]]; then
        log_success "Created: docs/infra/production.svg"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    echo ""
    echo "=========================================="
    echo "  AWS Infrastructure Audit - Book Vault"
    echo "  Version: ${AUDIT_VERSION}"
    echo "=========================================="
    echo ""

    check_prerequisites

    # Create output directories
    mkdir -p "${RAW_DIR}" "${DOCS_DIR}"

    # Initialize gaps file
    echo -n "" > "${OUT_DIR}/gaps.jsonl"

    check_aws_auth

    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run complete - setup validated"
        exit 0
    fi

    echo ""
    log_info "Starting infrastructure discovery..."
    echo ""

    discover_networking
    discover_compute
    discover_data
    discover_edge
    discover_security
    discover_observability

    echo ""
    log_info "Discovery complete. Processing data..."
    echo ""

    normalize_data
    generate_outputs

    # Convert gaps.jsonl to proper JSON array
    if [[ -s "${OUT_DIR}/gaps.jsonl" ]]; then
        jq -s '.' "${OUT_DIR}/gaps.jsonl" > "${OUT_DIR}/gaps.json"
        rm "${OUT_DIR}/gaps.jsonl"
        log_warn "Some resources could not be queried - see out/gaps.json"
    else
        echo "[]" > "${OUT_DIR}/gaps.json"
        rm -f "${OUT_DIR}/gaps.jsonl"
    fi

    echo ""
    echo "=========================================="
    echo "  Audit Complete!"
    echo "=========================================="
    echo ""
    echo "Outputs:"
    echo "  - ${OUT_DIR}/summary.json (machine-readable inventory)"
    echo "  - ${DOCS_DIR}/production.md (documentation)"
    echo "  - ${DOCS_DIR}/production.dot (diagram source)"
    if [[ "$SKIP_DIAGRAM" != "true" ]]; then
        echo "  - ${DOCS_DIR}/production.svg (rendered diagram)"
    fi
    echo ""

    if [[ -s "${OUT_DIR}/gaps.json" ]] && [[ "$(jq 'length' "${OUT_DIR}/gaps.json")" -gt 0 ]]; then
        echo "Warnings:"
        echo "  - $(jq 'length' "${OUT_DIR}/gaps.json") permission errors - see out/gaps.json"
        echo ""
    fi
}

main "$@"
