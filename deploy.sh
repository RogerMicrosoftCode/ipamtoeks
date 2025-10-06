#!/bin/bash

###############################################################################
# APIM to EKS Integration - Deployment Script
# This script deploys the integration components to EKS
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Function to update kubeconfig
update_kubeconfig() {
    log_info "Updating kubeconfig for EKS cluster..."
    
    aws eks update-kubeconfig \
        --name "$EKS_CLUSTER_NAME" \
        --region "$EKS_REGION"
    
    if [ $? -eq 0 ]; then
        log_info "Kubeconfig updated successfully"
    else
        log_error "Failed to update kubeconfig"
        exit 1
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    log_info "Ensuring namespace exists..."
    
    kubectl get namespace "$EKS_NAMESPACE" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        kubectl create namespace "$EKS_NAMESPACE"
        log_info "Namespace '$EKS_NAMESPACE' created"
    else
        log_info "Namespace '$EKS_NAMESPACE' already exists"
    fi
}

# Function to create deployment manifest
create_deployment_manifest() {
    log_info "Creating deployment manifest..."
    
    cat > /tmp/apim-eks-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${EKS_NAMESPACE}
  labels:
    app: apim-connector
spec:
  replicas: 3
  selector:
    matchLabels:
      app: apim-connector
  template:
    metadata:
      labels:
        app: apim-connector
    spec:
      containers:
      - name: apim-connector
        image: ${CONTAINER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
        ports:
        - containerPort: 8080
        env:
        - name: APIM_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${TOKEN_SECRET_NAME}
              key: token
        - name: APIM_SERVICE_URL
          value: "https://${APIM_SERVICE_NAME}.azure-api.net"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: ${HEALTH_CHECK_INTERVAL}
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: ${DEPLOYMENT_NAME}-service
  namespace: ${EKS_NAMESPACE}
spec:
  selector:
    app: apim-connector
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: LoadBalancer
EOF
    
    log_info "Deployment manifest created"
}

# Function to create service account for AWS access
create_service_account() {
    log_info "Creating service account with IAM role..."
    
    cat > /tmp/service-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: apim-eks-sa
  namespace: ${EKS_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/apim-eks-role
EOF
    
    kubectl apply -f /tmp/service-account.yaml
    
    if [ $? -eq 0 ]; then
        log_info "Service account created successfully"
    else
        log_warn "Failed to create service account (may already exist)"
    fi
}

# Function to apply deployment
apply_deployment() {
    log_info "Applying deployment to EKS..."
    
    kubectl apply -f /tmp/apim-eks-deployment.yaml
    
    if [ $? -eq 0 ]; then
        log_info "Deployment applied successfully"
    else
        log_error "Failed to apply deployment"
        exit 1
    fi
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    log_info "Waiting for deployment to be ready..."
    
    kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${EKS_NAMESPACE} --timeout=300s
    
    if [ $? -eq 0 ]; then
        log_info "Deployment is ready"
    else
        log_error "Deployment failed to become ready"
        exit 1
    fi
}

# Function to get service endpoint
get_service_endpoint() {
    log_info "Retrieving service endpoint..."
    
    local endpoint=""
    local max_attempts=30
    local attempt=0
    
    while [ -z "$endpoint" ] && [ $attempt -lt $max_attempts ]; do
        endpoint=$(kubectl get service ${DEPLOYMENT_NAME}-service -n ${EKS_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        
        if [ -z "$endpoint" ]; then
            log_info "Waiting for LoadBalancer endpoint... (attempt $((attempt+1))/$max_attempts)"
            sleep 10
            ((attempt++))
        fi
    done
    
    if [ -n "$endpoint" ]; then
        log_info "Service endpoint: $endpoint"
        echo "$endpoint" > /tmp/service-endpoint.txt
    else
        log_warn "Could not retrieve service endpoint (may still be provisioning)"
    fi
}

# Function to rollback deployment
rollback_deployment() {
    log_info "Rolling back deployment..."
    
    kubectl rollout undo deployment/${DEPLOYMENT_NAME} -n ${EKS_NAMESPACE}
    
    if [ $? -eq 0 ]; then
        log_info "Deployment rolled back successfully"
    else
        log_error "Failed to rollback deployment"
        exit 1
    fi
}

# Function to delete deployment
delete_deployment() {
    log_info "Deleting deployment..."
    
    kubectl delete -f /tmp/apim-eks-deployment.yaml
    
    if [ $? -eq 0 ]; then
        log_info "Deployment deleted successfully"
    else
        log_error "Failed to delete deployment"
        exit 1
    fi
}

# Function to check deployment health
check_health() {
    log_info "Checking deployment health..."
    
    local ready_replicas=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${EKS_NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    local desired_replicas=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${EKS_NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null)
    
    log_info "Ready replicas: $ready_replicas/$desired_replicas"
    
    if [ "$ready_replicas" == "$desired_replicas" ]; then
        log_info "Deployment is healthy"
        return 0
    else
        log_warn "Deployment is not fully healthy"
        return 1
    fi
}

# Main function
main() {
    log_info "=== APIM to EKS Deployment ==="
    
    case "${1:-deploy}" in
        deploy)
            check_prerequisites
            update_kubeconfig
            create_namespace
            create_deployment_manifest
            create_service_account
            apply_deployment
            wait_for_deployment
            get_service_endpoint
            check_health
            log_info "Deployment completed successfully"
            ;;
        rollback)
            if [ "$ENABLE_ROLLBACK" != "true" ]; then
                log_error "Rollback is disabled in configuration"
                exit 1
            fi
            check_prerequisites
            update_kubeconfig
            rollback_deployment
            ;;
        delete)
            check_prerequisites
            update_kubeconfig
            delete_deployment
            ;;
        health)
            check_prerequisites
            update_kubeconfig
            check_health
            ;;
        *)
            echo "Usage: $0 {deploy|rollback|delete|health}"
            echo "  deploy   - Deploy the integration to EKS"
            echo "  rollback - Rollback to previous deployment"
            echo "  delete   - Delete the deployment"
            echo "  health   - Check deployment health"
            exit 1
            ;;
    esac
}

main "$@"
