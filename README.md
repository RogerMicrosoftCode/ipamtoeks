# APIM to EKS Integration

Automated pipeline for deploying and managing integrations between Azure API Management (APIM) and Amazon Elastic Kubernetes Service (EKS) with independent token configuration.

## Overview

This project provides a comprehensive automation solution for:
- **Pipeline Automation**: Complete CI/CD pipeline for APIM to EKS integration
- **Deployment Management**: Automated deployment to EKS with health checks and rollback support
- **Token Management**: Independent token generation, rotation, and synchronization between APIM and EKS

## Features

- ✅ Automated token generation and synchronization
- ✅ Secure token storage in Azure Key Vault and AWS Secrets Manager
- ✅ Kubernetes secret management for EKS
- ✅ Automated deployment with health checks
- ✅ Rollback support for failed deployments
- ✅ Service endpoint discovery
- ✅ Cloud provider authentication validation
- ✅ Configuration validation
- ✅ Comprehensive logging and error handling

## Prerequisites

Before using this automation, ensure you have the following tools installed:

- **AWS CLI** (v2.x or higher)
- **Azure CLI** (v2.x or higher)
- **kubectl** (v1.20 or higher)
- **Docker** (for building container images)
- **OpenSSL** (for token generation)

### Authentication Requirements

1. **Azure**: Run `az login` and authenticate with your Azure account
2. **AWS**: Configure AWS credentials using `aws configure` or environment variables

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/RogerMicrosoftCode/ipamtoeks.git
cd ipamtoeks
```

### 2. Configure the Environment

```bash
# Copy the example configuration
cp config.example.env config.env

# Edit the configuration file with your settings
nano config.env
```

### 3. Make Scripts Executable

```bash
chmod +x pipeline.sh deploy.sh token-manager.sh
```

### 4. Run the Pipeline

```bash
# Run the complete pipeline
./pipeline.sh run

# Or just use the default command
./pipeline.sh
```

## Configuration

Edit `config.env` to customize your deployment:

### APIM Configuration
- `APIM_RESOURCE_GROUP`: Azure resource group containing APIM
- `APIM_SERVICE_NAME`: Name of your APIM service
- `APIM_SUBSCRIPTION_ID`: Azure subscription ID
- `APIM_API_ID`: API identifier in APIM
- `APIM_PRODUCT_ID`: Product identifier in APIM

### EKS Configuration
- `EKS_CLUSTER_NAME`: Name of your EKS cluster
- `EKS_REGION`: AWS region where EKS is deployed
- `EKS_NAMESPACE`: Kubernetes namespace for deployment
- `AWS_ACCOUNT_ID`: Your AWS account ID

### Token Configuration
- `TOKEN_SECRET_NAME`: Name for the shared token secret
- `TOKEN_EXPIRY_DAYS`: Token expiration period (default: 90 days)
- `TOKEN_ROTATION_ENABLED`: Enable automatic token rotation

### Deployment Configuration
- `DEPLOYMENT_NAME`: Name for the Kubernetes deployment
- `CONTAINER_REGISTRY`: Container registry URL
- `IMAGE_NAME`: Docker image name
- `IMAGE_TAG`: Docker image tag

## Usage

### Pipeline Commands

```bash
# Run the complete pipeline
./pipeline.sh run

# Check deployment status
./pipeline.sh status

# Clean up all resources
./pipeline.sh cleanup

# Show help
./pipeline.sh help
```

### Deployment Commands

```bash
# Deploy to EKS
./deploy.sh deploy

# Check deployment health
./deploy.sh health

# Rollback to previous version
./deploy.sh rollback

# Delete deployment
./deploy.sh delete
```

### Token Management Commands

```bash
# Create new token and sync across services
./token-manager.sh create

# Rotate existing token
./token-manager.sh rotate

# Verify token synchronization
./token-manager.sh verify
```

## Architecture

```
┌─────────────────────┐         ┌─────────────────────┐
│   Azure APIM        │         │   AWS EKS           │
│                     │         │                     │
│  ┌──────────────┐   │         │  ┌──────────────┐   │
│  │ API Gateway  │   │         │  │   Pods       │   │
│  └──────────────┘   │         │  └──────────────┘   │
│         │           │         │         │           │
│         ▼           │         │         ▼           │
│  ┌──────────────┐   │         │  ┌──────────────┐   │
│  │ Key Vault    │   │◄───────►│  │ Secrets Mgr  │   │
│  │ (Token)      │   │  Sync   │  │ (Token)      │   │
│  └──────────────┘   │         │  └──────────────┘   │
└─────────────────────┘         └─────────────────────┘
         │                               │
         └───────────Token────────────────┘
                 Synchronization
```

## Pipeline Workflow

The complete pipeline executes the following steps:

1. **Tool Validation**: Checks for required CLI tools
2. **Configuration Validation**: Validates all required environment variables
3. **Authentication**: Verifies cloud provider credentials
4. **Image Build**: Builds and pushes Docker image to registry
5. **Token Management**: Creates and syncs authentication tokens
6. **EKS Deployment**: Deploys the integration to EKS
7. **Verification**: Verifies deployment health and token sync

## Security Best Practices

1. **Never commit `config.env`** - It contains sensitive information
2. **Use `.gitignore`** - Ensure sensitive files are excluded from version control
3. **Rotate tokens regularly** - Use the token rotation feature
4. **Use IAM roles** - Configure IRSA (IAM Roles for Service Accounts) for EKS
5. **Enable encryption** - Ensure secrets are encrypted at rest
6. **Audit access** - Monitor access to Key Vault and Secrets Manager

## Troubleshooting

### Common Issues

**Authentication Failures**
```bash
# Re-authenticate with Azure
az login

# Re-configure AWS credentials
aws configure
```

**Deployment Issues**
```bash
# Check pod logs
kubectl logs -n <namespace> -l app=apim-connector

# Describe deployment
kubectl describe deployment <deployment-name> -n <namespace>
```

**Token Sync Issues**
```bash
# Verify token synchronization
./token-manager.sh verify

# Re-create tokens
./token-manager.sh create
```

### Logs

Check logs from deployed pods:
```bash
kubectl logs -f deployment/<deployment-name> -n <namespace>
```

### Health Checks

The deployment includes automatic health checks:
- **Liveness Probe**: `/health` endpoint
- **Readiness Probe**: `/ready` endpoint

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For issues and questions:
- Open an issue on GitHub
- Check existing documentation
- Review troubleshooting section

## Changelog

### Version 1.0.0
- Initial release
- Pipeline automation
- Token management
- EKS deployment
- Health checks and rollback support
