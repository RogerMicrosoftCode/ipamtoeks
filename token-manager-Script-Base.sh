#!/bin/bash

###############################################################################
# APIM to EKS Integration - Token Management Script
# This script handles the creation, rotation, and synchronization of tokens
# between Azure API Management (APIM) and AWS EKS
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: config.env not found. Copy config.example.env to config.env and configure it.${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate a secure token
generate_token() {
    local token_length=${1:-64}
    openssl rand -base64 $token_length | tr -d "=+/" | cut -c1-$token_length
}

# Function to create token in Azure Key Vault (for APIM)
create_apim_token() {
    log_info "Creating token in Azure Key Vault for APIM..."
    
    local token=$(generate_token)
    local secret_name="${TOKEN_SECRET_NAME}-apim"
    
    # Store in Azure Key Vault
    az keyvault secret set \
        --vault-name "${APIM_SERVICE_NAME}-kv" \
        --name "$secret_name" \
        --value "$token" \
        --expires "$(date -u -d "+${TOKEN_EXPIRY_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)" \
        > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "Token created successfully in Azure Key Vault"
        echo "$token"
    else
        log_error "Failed to create token in Azure Key Vault"
        exit 1
    fi
}

# Function to create token in AWS Secrets Manager (for EKS)
create_eks_token() {
    log_info "Creating token in AWS Secrets Manager for EKS..."
    
    local token="$1"
    local secret_name="${TOKEN_SECRET_NAME}-eks"
    
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
            --secret-string "$token" \
            --region "$EKS_REGION" > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_info "Token created/updated successfully in AWS Secrets Manager"
    else
        log_error "Failed to create token in AWS Secrets Manager"
        exit 1
    fi
}

# Function to sync token to Kubernetes secret
sync_token_to_k8s() {
    log_info "Syncing token to Kubernetes secret..."
    
    local token="$1"
    local secret_name="${TOKEN_SECRET_NAME}"
    
    # Update kubeconfig
    aws eks update-kubeconfig \
        --name "$EKS_CLUSTER_NAME" \
        --region "$EKS_REGION" > /dev/null 2>&1
    
    # Check if secret exists
    kubectl get secret "$secret_name" -n "$EKS_NAMESPACE" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # Delete existing secret
        kubectl delete secret "$secret_name" -n "$EKS_NAMESPACE" > /dev/null 2>&1
    fi
    
    # Create new secret
    kubectl create secret generic "$secret_name" \
        --from-literal=token="$token" \
        --namespace="$EKS_NAMESPACE" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "Token synced successfully to Kubernetes"
    else
        log_error "Failed to sync token to Kubernetes"
        exit 1
    fi
}

# Function to configure APIM subscription with token
configure_apim_subscription() {
    log_info "Configuring APIM subscription with token..."
    
    local token="$1"
    
    # Update APIM subscription key
    az apim api operation update \
        --resource-group "$APIM_RESOURCE_GROUP" \
        --service-name "$APIM_SERVICE_NAME" \
        --api-id "$APIM_API_ID" \
        --subscription-id "$APIM_SUBSCRIPTION_ID" \
        --set properties.subscriptionKeyParameterNames.header="X-API-Token" \
        > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "APIM subscription configured successfully"
    else
        log_warn "Failed to configure APIM subscription (may require manual setup)"
    fi
}

# Function to rotate tokens
rotate_tokens() {
    log_info "Starting token rotation..."
    
    # Generate new token
    local new_token=$(generate_token)
    
    # Create in APIM
    create_apim_token
    
    # Create in EKS
    create_eks_token "$new_token"
    
    # Sync to K8s
    sync_token_to_k8s "$new_token"
    
    # Configure APIM
    configure_apim_subscription "$new_token"
    
    log_info "Token rotation completed successfully"
}

# Function to verify token synchronization
verify_token_sync() {
    log_info "Verifying token synchronization..."
    
    local apim_token=$(az keyvault secret show \
        --vault-name "${APIM_SERVICE_NAME}-kv" \
        --name "${TOKEN_SECRET_NAME}-apim" \
        --query value -o tsv 2>/dev/null)
    
    local eks_token=$(aws secretsmanager get-secret-value \
        --secret-id "${TOKEN_SECRET_NAME}-eks" \
        --region "$EKS_REGION" \
        --query SecretString -o text 2>/dev/null)
    
    if [ "$apim_token" == "$eks_token" ]; then
        log_info "Tokens are synchronized"
        return 0
    else
        log_error "Tokens are NOT synchronized"
        return 1
    fi
}

# Main function
main() {
    log_info "=== APIM to EKS Token Management ==="
    
    case "${1:-create}" in
        create)
            log_info "Creating new token and syncing across services..."
            local token=$(create_apim_token)
            create_eks_token "$token"
            sync_token_to_k8s "$token"
            configure_apim_subscription "$token"
            log_info "Token creation and synchronization completed"
            ;;
        rotate)
            rotate_tokens
            ;;
        verify)
            verify_token_sync
            ;;
        *)
            echo "Usage: $0 {create|rotate|verify}"
            echo "  create  - Create new token and sync across all services"
            echo "  rotate  - Rotate existing token"
            echo "  verify  - Verify token synchronization"
            exit 1
            ;;
    esac
}

main "$@"
