#!/bin/bash

###############################################################################
# APIM Self-Hosted Gateway Token Management Script
# Obtiene tokens reales de Azure APIM y los sincroniza a Kubernetes
# Soporta múltiples gateways y almacenamiento híbrido (Azure KV + AWS SM)
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: config.env not found. Copy config.example.env to config.env and configure it.${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Default values if not set in config
BACKUP_DIR="${BACKUP_DIR:-/var/apim-backup}"
LOG_FILE="${LOG_FILE:-/var/log/apim-token-sync.log}"
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-false}"

###############################################################################
# LOGGING FUNCTIONS
###############################################################################

log_to_file() {
    local message="$1"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
    log_to_file "INFO: $message"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message"
    log_to_file "WARN: $message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    log_to_file "ERROR: $message"
}

log_debug() {
    local message="$1"
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $message"
        log_to_file "DEBUG: $message"
    fi
}

###############################################################################
# NOTIFICATION FUNCTIONS
###############################################################################

send_slack_notification() {
    local status="$1"
    local message="$2"
    
    if [ "$ENABLE_NOTIFICATIONS" != "true" ] || [ -z "$SLACK_WEBHOOK_URL" ]; then
        return 0
    fi
    
    local color="good"
    local emoji="✅"
    
    if [ "$status" = "error" ]; then
        color="danger"
        emoji="❌"
    elif [ "$status" = "warning" ]; then
        color="warning"
        emoji="⚠️"
    fi
    
    local payload=$(cat <<EOF
{
  "text": "$emoji APIM Token Sync: $status",
  "attachments": [{
    "color": "$color",
    "fields": [
      {"title": "Gateway ID", "value": "$GATEWAY_ID", "short": true},
      {"title": "Cluster", "value": "$EKS_CLUSTER_NAME", "short": true},
      {"title": "Message", "value": "$message", "short": false},
      {"title": "Timestamp", "value": "$(date '+%Y-%m-%d %H:%M:%S')", "short": true}
    ]
  }]
}
EOF
)
    
    curl -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        --silent --show-error > /dev/null 2>&1 || true
}

###############################################################################
# AZURE AUTHENTICATION
###############################################################################

azure_login() {
    log_info "Authenticating with Azure..."
    
    if [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ] && [ -n "$AZURE_TENANT_ID" ]; then
        # Service Principal authentication
        az login --service-principal \
            --username "$AZURE_CLIENT_ID" \
            --password "$AZURE_CLIENT_SECRET" \
            --tenant "$AZURE_TENANT_ID" > /dev/null 2>&1
    else
        # Managed Identity or az cli default authentication
        az login --identity > /dev/null 2>&1 || az account show > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_info "✅ Azure authentication successful"
        return 0
    else
        log_error "❌ Azure authentication failed"
        send_slack_notification "error" "Azure authentication failed"
        return 1
    fi
}

azure_logout() {
    az logout > /dev/null 2>&1 || true
}

###############################################################################
# TOKEN RETRIEVAL FROM APIM
###############################################################################

get_apim_gateway_token() {
    log_info "Fetching token from APIM Gateway..."
    
    local token=$(az apim gateway list-keys \
        --resource-group "$APIM_RESOURCE_GROUP" \
        --service-name "$APIM_SERVICE_NAME" \
        --gateway-id "$GATEWAY_ID" \
        --query "primaryKey" \
        --output tsv 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$token" ] && [ "$token" != "null" ]; then
        log_info "✅ Token retrieved successfully from APIM"
        log_debug "Token length: ${#token} characters"
        log_debug "Token preview: ${token:0:20}..."
        echo "$token"
        return 0
    else
        log_error "❌ Failed to retrieve token from APIM"
        log_error "Error: $token"
        send_slack_notification "error" "Failed to retrieve token from APIM: $token"
        return 1
    fi
}

get_apim_secondary_token() {
    log_info "Fetching secondary token from APIM Gateway..."
    
    local token=$(az apim gateway list-keys \
        --resource-group "$APIM_RESOURCE_GROUP" \
        --service-name "$APIM_SERVICE_NAME" \
        --gateway-id "$GATEWAY_ID" \
        --query "secondaryKey" \
        --output tsv 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$token" ] && [ "$token" != "null" ]; then
        log_info "✅ Secondary token retrieved successfully"
        echo "$token"
        return 0
    else
        log_warn "⚠️  Secondary token not available"
        return 1
    fi
}

###############################################################################
# KUBERNETES SECRET MANAGEMENT
###############################################################################

update_kubeconfig() {
    log_info "Updating kubeconfig for EKS cluster..."
    
    aws eks update-kubeconfig \
        --name "$EKS_CLUSTER_NAME" \
        --region "$EKS_REGION" \
        --alias "$EKS_CLUSTER_NAME" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "✅ Kubeconfig updated successfully"
        return 0
    else
        log_error "❌ Failed to update kubeconfig"
        send_slack_notification "error" "Failed to update kubeconfig for cluster $EKS_CLUSTER_NAME"
        return 1
    fi
}

get_current_k8s_token() {
    local secret_name="$1"
    local namespace="$2"
    
    kubectl get secret "$secret_name" \
        -n "$namespace" \
        -o jsonpath='{.data.access-token}' 2>/dev/null | base64 -d || echo ""
}

create_or_update_k8s_secret() {
    local token="$1"
    local secret_name="${K8S_SECRET_NAME}"
    local namespace="${EKS_NAMESPACE}"
    
    log_info "Creating/updating Kubernetes secret..."
    
    # Check if namespace exists
    kubectl get namespace "$namespace" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_info "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    fi
    
    # Check if secret exists
    kubectl get secret "$secret_name" -n "$namespace" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # Secret exists, check if token changed
        local current_token=$(get_current_k8s_token "$secret_name" "$namespace")
        
        if [ "$current_token" = "$token" ]; then
            log_info "ℹ️  Token unchanged, no update needed"
            return 0
        fi
        
        # Update existing secret using patch
        log_info "Updating existing secret..."
        kubectl patch secret "$secret_name" \
            -n "$namespace" \
            -p "{\"data\":{\"access-token\":\"$(echo -n $token | base64 -w 0)\"}}" > /dev/null 2>&1
    else
        # Create new secret
        log_info "Creating new secret..."
        kubectl create secret generic "$secret_name" \
            --from-literal=access-token="$token" \
            --from-literal=gateway-id="$GATEWAY_ID" \
            --namespace="$namespace" > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_info "✅ Kubernetes secret updated successfully"
        
        # Add labels for better management
        kubectl label secret "$secret_name" \
            -n "$namespace" \
            app=apim-gateway \
            gateway-id="$GATEWAY_ID" \
            managed-by=apim-token-sync \
            --overwrite > /dev/null 2>&1
        
        return 0
    else
        log_error "❌ Failed to update Kubernetes secret"
        send_slack_notification "error" "Failed to update Kubernetes secret $secret_name"
        return 1
    fi
}

###############################################################################
# AWS SECRETS MANAGER (OPTIONAL)
###############################################################################

store_token_in_aws_secrets_manager() {
    local token="$1"
    local secret_name="${TOKEN_SECRET_NAME:-apim-gateway-token}"
    
    if [ "${ENABLE_AWS_SECRETS_MANAGER:-false}" != "true" ]; then
        log_debug "AWS Secrets Manager storage disabled"
        return 0
    fi
    
    log_info "Storing token in AWS Secrets Manager..."
    
    # Check if secret exists
    aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --region "$EKS_REGION" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # Update existing secret
        aws secretsmanager update-secret \
            --secret-id "$secret_name" \
            --secret-string "$token" \
            --region "$EKS_REGION" > /dev/null 2>&1
    else
        # Create new secret
        aws secretsmanager create-secret \
            --name "$secret_name" \
            --description "APIM Gateway token for $GATEWAY_ID" \
            --secret-string "$token" \
            --region "$EKS_REGION" \
            --tags Key=Gateway,Value="$GATEWAY_ID" Key=ManagedBy,Value=apim-token-sync \
            > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_info "✅ Token stored in AWS Secrets Manager"
        return 0
    else
        log_warn "⚠️  Failed to store token in AWS Secrets Manager"
        return 1
    fi
}

###############################################################################
# AZURE KEY VAULT (OPTIONAL)
###############################################################################

store_token_in_azure_keyvault() {
    local token="$1"
    local secret_name="${KEYVAULT_SECRET_NAME:-apim-gateway-token}"
    
    if [ "${ENABLE_AZURE_KEYVAULT:-false}" != "true" ] || [ -z "$KEYVAULT_NAME" ]; then
        log_debug "Azure Key Vault storage disabled"
        return 0
    fi
    
    log_info "Storing token in Azure Key Vault..."
    
    local expiry_date=$(date -u -d "+${TOKEN_EXPIRY_DAYS:-90} days" +%Y-%m-%dT%H:%M:%SZ)
    
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "$secret_name" \
        --value "$token" \
        --expires "$expiry_date" \
        --tags gateway-id="$GATEWAY_ID" managed-by=apim-token-sync \
        > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "✅ Token stored in Azure Key Vault"
        return 0
    else
        log_warn "⚠️  Failed to store token in Azure Key Vault"
        return 1
    fi
}

###############################################################################
# BACKUP MANAGEMENT
###############################################################################

create_token_backup() {
    local token="$1"
    
    log_info "Creating token backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    local backup_file="$BACKUP_DIR/token-backup-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$backup_file" <<EOF
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Gateway ID: $GATEWAY_ID
APIM Service: $APIM_SERVICE_NAME
Resource Group: $APIM_RESOURCE_GROUP
EKS Cluster: $EKS_CLUSTER_NAME
Token: $token
EOF
    
    chmod 600 "$backup_file"
    
    # Keep only last N backups
    local max_backups=${MAX_BACKUPS:-10}
    local backup_count=$(ls -1 "$BACKUP_DIR"/token-backup-*.txt 2>/dev/null | wc -l)
    
    if [ "$backup_count" -gt "$max_backups" ]; then
        log_info "Cleaning old backups (keeping last $max_backups)..."
        ls -t "$BACKUP_DIR"/token-backup-*.txt | tail -n +$((max_backups + 1)) | xargs -r rm
    fi
    
    log_info "✅ Backup created: $backup_file"
}

###############################################################################
# POD RESTART (OPTIONAL)
###############################################################################

restart_gateway_pods() {
    if [ "${RESTART_PODS:-false}" != "true" ]; then
        log_info "ℹ️  Pod restart disabled (set RESTART_PODS=true to enable)"
        return 0
    fi
    
    log_info "Restarting gateway pods..."
    
    local deployment_name="${GATEWAY_DEPLOYMENT_NAME:-apim-gateway}"
    local namespace="${EKS_NAMESPACE}"
    
    kubectl rollout restart deployment/"$deployment_name" -n "$namespace" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "⏳ Waiting for rollout to complete..."
        kubectl rollout status deployment/"$deployment_name" -n "$namespace" --timeout=5m
        
        if [ $? -eq 0 ]; then
            log_info "✅ Pods restarted successfully"
            return 0
        else
            log_warn "⚠️  Pod restart timeout"
            return 1
        fi
    else
        log_warn "⚠️  Failed to restart pods"
        return 1
    fi
}

###############################################################################
# VERIFICATION
###############################################################################

verify_token_sync() {
    log_info "Verifying token synchronization..."
    
    local secret_name="${K8S_SECRET_NAME}"
    local namespace="${EKS_NAMESPACE}"
    
    # Get token from K8s
    local k8s_token=$(get_current_k8s_token "$secret_name" "$namespace")
    
    if [ -z "$k8s_token" ]; then
        log_error "❌ Token not found in Kubernetes secret"
        return 1
    fi
    
    # Verify token format (basic validation)
    if [ ${#k8s_token} -lt 20 ]; then
        log_error "❌ Token appears invalid (too short)"
        return 1
    fi
    
    log_info "✅ Token verification successful"
    log_debug "Token length: ${#k8s_token} characters"
    
    return 0
}

verify_gateway_connectivity() {
    log_info "Verifying gateway connectivity to APIM..."
    
    # This is a basic check - actual connectivity test depends on your setup
    az apim gateway show \
        --resource-group "$APIM_RESOURCE_GROUP" \
        --service-name "$APIM_SERVICE_NAME" \
        --gateway-id "$GATEWAY_ID" \
        --query "name" -o tsv > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "✅ Gateway exists in APIM"
        return 0
    else
        log_error "❌ Gateway not found in APIM"
        return 1
    fi
}

###############################################################################
# MAIN OPERATIONS
###############################################################################

sync_token() {
    log_info "=========================================="
    log_info "Starting token synchronization..."
    log_info "Gateway ID: $GATEWAY_ID"
    log_info "APIM Service: $APIM_SERVICE_NAME"
    log_info "EKS Cluster: $EKS_CLUSTER_NAME"
    log_info "=========================================="
    
    # Step 1: Authenticate with Azure
    azure_login || exit 1
    
    # Step 2: Get token from APIM
    local token=$(get_apim_gateway_token)
    if [ $? -ne 0 ] || [ -z "$token" ]; then
        azure_logout
        exit 1
    fi
    
    # Step 3: Update kubeconfig
    update_kubeconfig || exit 1
    
    # Step 4: Update Kubernetes secret
    create_or_update_k8s_secret "$token" || exit 1
    
    # Step 5: Store in AWS Secrets Manager (optional)
    store_token_in_aws_secrets_manager "$token"
    
    # Step 6: Store in Azure Key Vault (optional)
    store_token_in_azure_keyvault "$token"
    
    # Step 7: Create backup
    create_token_backup "$token"
    
    # Step 8: Restart pods (optional)
    restart_gateway_pods
    
    # Step 9: Verify
    verify_token_sync
    
    # Cleanup
    azure_logout
    
    log_info "=========================================="
    log_info "✅ Token synchronization completed successfully"
    log_info "=========================================="
    
    send_slack_notification "success" "Token synchronized successfully for gateway $GATEWAY_ID"
}

rotate_token() {
    log_info "=========================================="
    log_info "Starting token rotation..."
    log_info "=========================================="
    
    # Token rotation in APIM requires regenerating the key
    azure_login || exit 1
    
    log_info "Regenerating APIM Gateway token..."
    
    az apim gateway regenerate-key \
        --resource-group "$APIM_RESOURCE_GROUP" \
        --service-name "$APIM_SERVICE_NAME" \
        --gateway-id "$GATEWAY_ID" \
        --key-type primary > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "✅ Token regenerated in APIM"
        
        # Wait a moment for the change to propagate
        sleep 5
        
        # Now sync the new token
        azure_logout
        sync_token
    else
        log_error "❌ Failed to regenerate token in APIM"
        azure_logout
        send_slack_notification "error" "Failed to regenerate token for gateway $GATEWAY_ID"
        exit 1
    fi
}

show_status() {
    log_info "=========================================="
    log_info "APIM Gateway Token Status"
    log_info "=========================================="
    
    azure_login || exit 1
    update_kubeconfig || exit 1
    
    # Gateway info
    log_info "Gateway ID: $GATEWAY_ID"
    log_info "APIM Service: $APIM_SERVICE_NAME"
    log_info "EKS Cluster: $EKS_CLUSTER_NAME"
    log_info ""
    
    # Check gateway exists
    verify_gateway_connectivity
    
    # Check K8s secret
    local k8s_token=$(get_current_k8s_token "$K8S_SECRET_NAME" "$EKS_NAMESPACE")
    if [ -n "$k8s_token" ]; then
        log_info "✅ Token exists in Kubernetes secret"
        log_info "   Token length: ${#k8s_token} characters"
    else
        log_warn "⚠️  Token not found in Kubernetes secret"
    fi
    
    # Check last backup
    if [ -d "$BACKUP_DIR" ]; then
        local last_backup=$(ls -t "$BACKUP_DIR"/token-backup-*.txt 2>/dev/null | head -1)
        if [ -n "$last_backup" ]; then
            log_info "✅ Last backup: $(basename "$last_backup")"
        else
            log_warn "⚠️  No backups found"
        fi
    fi
    
    azure_logout
    
    log_info "=========================================="
}

###############################################################################
# MAIN ENTRY POINT
###############################################################################

main() {
    local command="${1:-sync}"
    
    case "$command" in
        sync)
            sync_token
            ;;
        rotate)
            rotate_token
            ;;
        verify)
            azure_login || exit 1
            update_kubeconfig || exit 1
            verify_token_sync
            verify_gateway_connectivity
            azure_logout
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            cat <<EOF
APIM Self-Hosted Gateway Token Management

Usage: $0 [COMMAND]

Commands:
    sync      Synchronize token from APIM to Kubernetes (default)
    rotate    Regenerate token in APIM and sync to Kubernetes
    verify    Verify token synchronization and gateway connectivity
    status    Show current status of gateway and tokens
    help      Show this help message

Environment:
    Configuration is loaded from config.env file

Examples:
    $0 sync           # Sync token (default operation)
    $0 rotate         # Rotate and sync token
    $0 verify         # Verify current setup
    $0 status         # Show status information

EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"