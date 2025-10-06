# Quick Start Guide

Get up and running with APIM to EKS integration in 5 minutes!

## 1. Prerequisites

Ensure you have these tools installed:
- AWS CLI v2+
- Azure CLI v2+
- kubectl v1.20+
- Docker
- OpenSSL

## 2. Initial Setup

```bash
# Clone the repository
git clone https://github.com/RogerMicrosoftCode/ipamtoeks.git
cd ipamtoeks

# Run interactive setup
./setup.sh
```

The setup script will prompt you for:
- Azure APIM details (resource group, service name, subscription ID)
- AWS EKS details (cluster name, region, account ID)
- Container registry URL

## 3. Authenticate

```bash
# Azure
az login

# AWS
aws configure
```

## 4. Run the Pipeline

```bash
# Execute the complete pipeline
./pipeline.sh run
```

This will:
1. ✓ Validate tools and configuration
2. ✓ Verify cloud authentication
3. ✓ Build and push container image
4. ✓ Create and sync tokens
5. ✓ Deploy to EKS
6. ✓ Verify deployment health

## 5. Verify Deployment

```bash
# Check deployment status
./pipeline.sh status

# Verify token synchronization
./token-manager.sh verify

# Check pod health
kubectl get pods -n <your-namespace>
```

## Common Commands

```bash
# Check deployment health
./deploy.sh health

# Rotate tokens
./token-manager.sh rotate

# View logs
kubectl logs -f deployment/<deployment-name> -n <namespace>

# Rollback deployment
./deploy.sh rollback

# Clean up resources
./pipeline.sh cleanup
```

## Troubleshooting

**Issue: "config.env not found"**
```bash
cp config.example.env config.env
# Edit config.env with your settings
```

**Issue: Authentication failed**
```bash
# Re-authenticate
az login
aws configure
```

**Issue: Deployment fails**
```bash
# Check logs
kubectl logs -l app=apim-connector -n <namespace>

# Check events
kubectl get events -n <namespace>
```

## Next Steps

- Review [README.md](README.md) for detailed documentation
- Check [TESTING.md](TESTING.md) for comprehensive testing guide
- Customize Kubernetes manifests in `k8s-*.yaml` files
- Update Dockerfile for your application needs

## Architecture Overview

```
Pipeline → Token Management → EKS Deployment → Verification
    ↓             ↓                  ↓              ↓
 Build        Azure KV          Kubernetes      Health
 Image        AWS SM            Secrets         Checks
```

## Support

For issues:
1. Check TESTING.md for troubleshooting steps
2. Review logs from failed steps
3. Open an issue on GitHub

## Security Notes

⚠️ Never commit `config.env` to version control
⚠️ Rotate tokens regularly using `./token-manager.sh rotate`
⚠️ Use IAM roles for production deployments
⚠️ Enable encryption for secrets at rest

---

That's it! You're ready to use APIM to EKS integration. 🚀
