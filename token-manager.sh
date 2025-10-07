###############################################################################
# APIM Token Sync Configuration
# Copy this file to config.env and update with your values
###############################################################################

# ============================================================================
# AZURE APIM CONFIGURATION
# ============================================================================

# Azure Resource Group where APIM is located
APIM_RESOURCE_GROUP="your-resource-group"

# Azure APIM Service Name
APIM_SERVICE_NAME="your-apim-service"

# Gateway ID in APIM (get from Azure Portal or az cli)
GATEWAY_ID="your-gateway-001"

# ============================================================================
# AZURE AUTHENTICATION
# ============================================================================

# Option 1: Service Principal (recommended for automation)
AZURE_CLIENT_ID="your-service-principal-client-id"
AZURE_CLIENT_SECRET="your-service-principal-secret"
AZURE_TENANT_ID="your-azure-tenant-id"

# Option 2: Managed Identity (leave above empty if using managed identity)
# The script will automatically use managed identity if SP credentials are not set

# ============================================================================
# AWS EKS CONFIGURATION
# ============================================================================

# EKS Cluster Name
EKS_CLUSTER_NAME="your-eks-cluster"

# AWS Region where EKS is located
EKS_REGION="us-east-1"

# Kubernetes Namespace for APIM Gateway
EKS_NAMESPACE="apim-gateway"

# ============================================================================
# KUBERNETES SECRET CONFIGURATION
# ============================================================================

# Name of the Kubernetes Secret to create/update
K8S_SECRET_NAME="apim-gateway-secret"

# Deployment name for optional pod restart
GATEWAY_DEPLOYMENT_NAME="apim-gateway"

# ============================================================================
# OPTIONAL: AWS SECRETS MANAGER
# ============================================================================

# Enable storage in AWS Secrets Manager (true/false)
ENABLE_AWS_SECRETS_MANAGER="false"

# Secret name in AWS Secrets Manager
TOKEN_SECRET_NAME="apim-gateway-token"

# ============================================================================
# OPTIONAL: AZURE KEY VAULT
# ============================================================================

# Enable storage in Azure Key Vault (true/false)
ENABLE_AZURE_KEYVAULT="false"

# Azure Key Vault Name
KEYVAULT_NAME="your-keyvault-name"

# Secret name in Key Vault
KEYVAULT_SECRET_NAME="apim-gateway-token"

# Token expiry days (for Key Vault only)
TOKEN_EXPIRY_DAYS="90"

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================

# Directory for token backups
BACKUP_DIR="/var/apim-backup"

# Maximum number of backups to keep
MAX_BACKUPS="10"

# ============================================================================
# OPERATIONAL SETTINGS
# ============================================================================

# Restart pods after token update (true/false)
RESTART_PODS="false"

# Log file location
LOG_FILE="/var/log/apim-token-sync.log"

# Enable debug logging (true/false)
DEBUG="false"

# ============================================================================
# NOTIFICATIONS
# ============================================================================

# Enable Slack notifications (true/false)
ENABLE_NOTIFICATIONS="false"

# Slack Webhook URL
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

###############################################################################
# END OF CONFIGURATION
###############################################################################