# Testing Guide

## Overview

This guide provides instructions for testing the APIM to EKS integration scripts.

## Prerequisites Testing

### Test Tool Availability

```bash
# Test AWS CLI
aws --version

# Test Azure CLI
az --version

# Test kubectl
kubectl version --client

# Test Docker
docker --version

# Test OpenSSL
openssl version
```

## Configuration Testing

### Test Configuration Validation

```bash
# Copy example configuration
cp config.example.env config.env

# Edit configuration with test values
nano config.env

# Test configuration validation
./pipeline.sh status
```

## Authentication Testing

### Test Azure Authentication

```bash
# Login to Azure
az login

# Verify authentication
az account show

# List resource groups
az group list --output table
```

### Test AWS Authentication

```bash
# Configure AWS credentials
aws configure

# Verify authentication
aws sts get-caller-identity

# List EKS clusters
aws eks list-clusters --region us-west-2
```

## Token Management Testing

### Test Token Generation

```bash
# Test token creation
./token-manager.sh create

# Verify token in Azure Key Vault
az keyvault secret list --vault-name <vault-name>

# Verify token in AWS Secrets Manager
aws secretsmanager list-secrets --region <region>
```

### Test Token Rotation

```bash
# Rotate tokens
./token-manager.sh rotate

# Verify synchronization
./token-manager.sh verify
```

## Deployment Testing

### Test Dry Run

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Test kubectl access
kubectl get nodes

# Test namespace creation
kubectl get namespace <namespace>
```

### Test Deployment

```bash
# Deploy to EKS
./deploy.sh deploy

# Check deployment status
kubectl get deployments -n <namespace>

# Check pods
kubectl get pods -n <namespace>

# Check services
kubectl get services -n <namespace>
```

### Test Health Checks

```bash
# Check deployment health
./deploy.sh health

# Check pod logs
kubectl logs -f deployment/<deployment-name> -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>
```

## Pipeline Testing

### Test Complete Pipeline

```bash
# Run complete pipeline
./pipeline.sh run

# Monitor pipeline execution
# The pipeline should complete all 7 steps successfully
```

### Test Status Command

```bash
# Check deployment status
./pipeline.sh status
```

## Integration Testing

### Test End-to-End Flow

1. **Setup**
   ```bash
   ./setup.sh
   ```

2. **Run Pipeline**
   ```bash
   ./pipeline.sh run
   ```

3. **Verify Deployment**
   ```bash
   kubectl get all -n <namespace>
   ```

4. **Test Service Endpoint**
   ```bash
   # Get service endpoint
   kubectl get service <service-name> -n <namespace>
   
   # Test endpoint (once LoadBalancer is ready)
   curl http://<endpoint>/health
   ```

5. **Verify Token Sync**
   ```bash
   ./token-manager.sh verify
   ```

## Rollback Testing

### Test Deployment Rollback

```bash
# Make a change to trigger rollback
# ... make changes ...

# Deploy new version
./deploy.sh deploy

# If deployment fails, test rollback
./deploy.sh rollback

# Verify rollback
kubectl rollout history deployment/<deployment-name> -n <namespace>
```

## Cleanup Testing

### Test Resource Cleanup

```bash
# Test cleanup
./pipeline.sh cleanup

# Verify resources are deleted
kubectl get all -n <namespace>
```

## Error Handling Testing

### Test Invalid Configuration

```bash
# Remove required config variable
# Run pipeline to test error handling
./pipeline.sh run

# Should fail with clear error message
```

### Test Missing Authentication

```bash
# Clear AWS credentials temporarily
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

# Run pipeline to test error handling
./pipeline.sh run

# Should fail with authentication error
```

## Performance Testing

### Test Deployment Time

```bash
# Time the deployment
time ./deploy.sh deploy

# Measure rollout time
time kubectl rollout status deployment/<deployment-name> -n <namespace>
```

## Security Testing

### Test Token Security

```bash
# Verify tokens are not in logs
kubectl logs deployment/<deployment-name> -n <namespace> | grep -i token

# Verify secrets are encrypted
kubectl get secret <secret-name> -n <namespace> -o yaml
```

### Test RBAC

```bash
# Verify service account
kubectl get serviceaccount apim-eks-sa -n <namespace>

# Verify role binding
kubectl get rolebinding -n <namespace>
```

## Monitoring and Logging

### Test Logging

```bash
# View deployment logs
kubectl logs -f deployment/<deployment-name> -n <namespace>

# View all pod logs
kubectl logs -l app=apim-connector -n <namespace> --all-containers
```

### Test Events

```bash
# View deployment events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Expected Results

### Successful Pipeline Run

```
✓ Tool validation passed
✓ Configuration validated
✓ Authentication successful
✓ Image built and pushed
✓ Tokens created and synced
✓ Deployment successful
✓ Health checks passed
```

### Successful Deployment

```
✓ Namespace created
✓ Service account created
✓ Deployment applied
✓ Pods running (3/3)
✓ Service endpoint available
✓ Health checks passing
```

## Troubleshooting Tests

### Debug Failed Deployment

```bash
# Check pod status
kubectl get pods -n <namespace>

# Describe problematic pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>
```

### Debug Network Issues

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Test service connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://<service-name>.<namespace>
```

## Test Checklist

- [ ] All prerequisites installed
- [ ] Configuration validated
- [ ] Azure authentication working
- [ ] AWS authentication working
- [ ] Token creation successful
- [ ] Token rotation working
- [ ] Token synchronization verified
- [ ] Deployment successful
- [ ] Pods running
- [ ] Service endpoint available
- [ ] Health checks passing
- [ ] Rollback working
- [ ] Cleanup working
- [ ] Error handling working
- [ ] Logging working
- [ ] Security controls in place
