#!/bin/bash

###############################################################################
# APIM to EKS Integration - Pipeline Automation Script
# This script orchestrates the complete CI/CD pipeline
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if all required tools are installed
check_tools() {
    log_step "1/7: Checking required tools..."
    
    local tools=("aws" "kubectl" "az" "docker" "openssl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_info "All required tools are installed"
}

# Function to validate configuration
validate_config() {
    log_step "2/7: Validating configuration..."
    
    local required_vars=(
        "APIM_RESOURCE_GROUP"
        "APIM_SERVICE_NAME"
        "EKS_CLUSTER_NAME"
        "EKS_REGION"
        "EKS_NAMESPACE"
        "DEPLOYMENT_NAME"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required configuration variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log_info "Configuration validated successfully"
}

# Function to authenticate with cloud providers
authenticate() {
    log_step "3/7: Authenticating with cloud providers..."
    
    # Check Azure authentication
    log_info "Checking Azure authentication..."
    az account show > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_warn "Not authenticated with Azure. Please run: az login"
        exit 1
    fi
    log_info "Azure authentication successful"
    
    # Check AWS authentication
    log_info "Checking AWS authentication..."
    aws sts get-caller-identity > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_warn "Not authenticated with AWS. Please configure AWS credentials"
        exit 1
    fi
    log_info "AWS authentication successful"
}

# Function to build and push container image
build_and_push_image() {
    log_step "4/7: Building and pushing container image..."
    
    if [ -f "${SCRIPT_DIR}/Dockerfile" ]; then
        log_info "Building Docker image..."
        
        docker build -t "${CONTAINER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}"
        
        if [ $? -eq 0 ]; then
            log_info "Docker image built successfully"
        else
            log_error "Failed to build Docker image"
            exit 1
        fi
        
        log_info "Pushing Docker image..."
        
        # Login to Azure Container Registry
        az acr login --name "${CONTAINER_REGISTRY%%.*}" 2>/dev/null || true
        
        docker push "${CONTAINER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        
        if [ $? -eq 0 ]; then
            log_info "Docker image pushed successfully"
        else
            log_error "Failed to push Docker image"
            exit 1
        fi
    else
        log_warn "Dockerfile not found, skipping image build"
    fi
}

# Function to manage tokens
manage_tokens() {
    log_step "5/7: Managing authentication tokens..."
    
    if [ -f "${SCRIPT_DIR}/token-manager.sh" ]; then
        bash "${SCRIPT_DIR}/token-manager.sh" create
    else
        log_warn "token-manager.sh not found, skipping token management"
    fi
}

# Function to deploy to EKS
deploy_to_eks() {
    log_step "6/7: Deploying to EKS..."
    
    if [ -f "${SCRIPT_DIR}/deploy.sh" ]; then
        bash "${SCRIPT_DIR}/deploy.sh" deploy
    else
        log_error "deploy.sh not found"
        exit 1
    fi
}

# Function to verify deployment
verify_deployment() {
    log_step "7/7: Verifying deployment..."
    
    # Check deployment health
    if [ -f "${SCRIPT_DIR}/deploy.sh" ]; then
        bash "${SCRIPT_DIR}/deploy.sh" health
    fi
    
    # Verify token synchronization
    if [ -f "${SCRIPT_DIR}/token-manager.sh" ]; then
        bash "${SCRIPT_DIR}/token-manager.sh" verify
    fi
    
    log_info "Deployment verification completed"
}

# Function to run full pipeline
run_pipeline() {
    log_info "=== Starting APIM to EKS Integration Pipeline ==="
    echo ""
    
    check_tools
    echo ""
    
    validate_config
    echo ""
    
    authenticate
    echo ""
    
    build_and_push_image
    echo ""
    
    manage_tokens
    echo ""
    
    deploy_to_eks
    echo ""
    
    verify_deployment
    echo ""
    
    log_info "=== Pipeline completed successfully ==="
    log_info "Your APIM to EKS integration is now deployed and ready to use"
}

# Function to show pipeline status
show_status() {
    log_info "=== Pipeline Status ==="
    
    # Check deployment status
    log_info "Checking EKS deployment..."
    kubectl get deployment ${DEPLOYMENT_NAME} -n ${EKS_NAMESPACE} 2>/dev/null || log_warn "Deployment not found"
    
    # Check service status
    log_info "Checking service..."
    kubectl get service ${DEPLOYMENT_NAME}-service -n ${EKS_NAMESPACE} 2>/dev/null || log_warn "Service not found"
    
    # Check pods
    log_info "Checking pods..."
    kubectl get pods -n ${EKS_NAMESPACE} -l app=apim-connector 2>/dev/null || log_warn "No pods found"
}

# Function to cleanup resources
cleanup() {
    log_info "=== Cleaning up resources ==="
    
    read -p "Are you sure you want to delete all resources? (yes/no): " confirm
    
    if [ "$confirm" == "yes" ]; then
        if [ -f "${SCRIPT_DIR}/deploy.sh" ]; then
            bash "${SCRIPT_DIR}/deploy.sh" delete
        fi
        log_info "Cleanup completed"
    else
        log_info "Cleanup cancelled"
    fi
}

# Function to show help
show_help() {
    cat <<EOF
APIM to EKS Integration Pipeline

Usage: $0 [command]

Commands:
  run       Run the complete pipeline (default)
  status    Show current deployment status
  cleanup   Clean up all deployed resources
  help      Show this help message

Pipeline Steps:
  1. Check required tools
  2. Validate configuration
  3. Authenticate with cloud providers
  4. Build and push container image
  5. Manage authentication tokens
  6. Deploy to EKS
  7. Verify deployment

Configuration:
  Edit config.env to configure the pipeline
  See config.example.env for reference

Examples:
  $0              # Run full pipeline
  $0 run          # Run full pipeline
  $0 status       # Check deployment status
  $0 cleanup      # Delete all resources

EOF
}

# Main function
main() {
    case "${1:-run}" in
        run)
            run_pipeline
            ;;
        status)
            show_status
            ;;
        cleanup)
            cleanup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
