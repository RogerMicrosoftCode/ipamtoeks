#!/bin/bash

###############################################################################
# APIM to EKS Integration - Setup Script
# This script helps set up the initial configuration
###############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== APIM to EKS Integration Setup ===${NC}\n"

# Check if config.env already exists
if [ -f "config.env" ]; then
    echo -e "${YELLOW}Warning: config.env already exists!${NC}"
    read -p "Do you want to overwrite it? (yes/no): " overwrite
    if [ "$overwrite" != "yes" ]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Create config.env from example
cp config.example.env config.env

echo -e "${GREEN}Configuration file created: config.env${NC}\n"

# Interactive configuration
echo "Let's configure your environment..."
echo ""

# APIM Configuration
echo -e "${BLUE}[Azure APIM Configuration]${NC}"
read -p "APIM Resource Group: " apim_rg
read -p "APIM Service Name: " apim_name
read -p "Azure Subscription ID: " subscription_id

sed -i "s/your-apim-resource-group/$apim_rg/g" config.env
sed -i "s/your-apim-service-name/$apim_name/g" config.env
sed -i "s/your-subscription-id/$subscription_id/g" config.env

echo ""

# EKS Configuration
echo -e "${BLUE}[AWS EKS Configuration]${NC}"
read -p "EKS Cluster Name: " eks_cluster
read -p "EKS Region (default: us-west-2): " eks_region
eks_region=${eks_region:-us-west-2}
read -p "AWS Account ID: " aws_account

sed -i "s/your-eks-cluster-name/$eks_cluster/g" config.env
sed -i "s/us-west-2/$eks_region/g" config.env
sed -i "s/your-aws-account-id/$aws_account/g" config.env

echo ""

# Container Registry
echo -e "${BLUE}[Container Registry]${NC}"
read -p "Container Registry (e.g., myregistry.azurecr.io): " registry

sed -i "s|your-registry.azurecr.io|$registry|g" config.env

echo ""

# Make scripts executable
chmod +x pipeline.sh deploy.sh token-manager.sh

echo -e "${GREEN}Setup completed successfully!${NC}\n"
echo "Next steps:"
echo "1. Review and edit config.env if needed"
echo "2. Authenticate with Azure: az login"
echo "3. Configure AWS credentials: aws configure"
echo "4. Run the pipeline: ./pipeline.sh run"
echo ""
