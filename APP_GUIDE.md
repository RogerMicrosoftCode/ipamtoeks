# Sample Application Structure

This directory can contain your application code that will be deployed to EKS.

## Example Structure

```
app/
├── server.js           # Main application server
├── healthcheck.js      # Health check endpoint
├── package.json        # Node.js dependencies
├── config/            
│   └── default.json    # Application configuration
├── routes/            
│   └── api.js          # API routes
└── middleware/        
    └── auth.js         # Authentication middleware
```

## Sample server.js

```javascript
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Middleware
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

// Ready check endpoint
app.get('/ready', (req, res) => {
  res.status(200).json({ status: 'ready' });
});

// API endpoint with APIM token validation
app.get('/api/v1/data', (req, res) => {
  const token = req.headers['x-api-token'];
  const expectedToken = process.env.APIM_TOKEN;
  
  if (token !== expectedToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  
  res.json({ message: 'Data from EKS', timestamp: new Date() });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

## Sample healthcheck.js

```javascript
const http = require('http');

const options = {
  hostname: 'localhost',
  port: 8080,
  path: '/health',
  timeout: 2000
};

const healthCheck = http.request(options, (res) => {
  if (res.statusCode === 200) {
    process.exit(0);
  } else {
    process.exit(1);
  }
});

healthCheck.on('error', () => {
  process.exit(1);
});

healthCheck.end();
```

## Sample package.json

```json
{
  "name": "apim-eks-connector",
  "version": "1.0.0",
  "description": "APIM to EKS integration connector",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "jest",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.4.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22",
    "jest": "^29.5.0"
  }
}
```

## Dockerfile

See `Dockerfile.example` in the root directory for a sample Dockerfile.

## Environment Variables

The application will receive the following environment variables:

- `APIM_TOKEN`: Authentication token from Kubernetes secret
- `APIM_SERVICE_URL`: APIM service endpoint
- `PORT`: Application port (default: 8080)

## Building Your Application

1. Add your application code to this directory
2. Update `Dockerfile.example` to `Dockerfile` with your build steps
3. Update `config.example.env` with your registry details
4. Run `./pipeline.sh run` to build and deploy

## Testing Locally

```bash
# Run with Docker
docker build -t apim-connector .
docker run -p 8080:8080 -e APIM_TOKEN=test apim-connector

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl -H "X-API-Token: test" http://localhost:8080/api/v1/data
```
