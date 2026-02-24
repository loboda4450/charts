# BewCloud Helm Chart

A Helm chart for deploying [BewCloud](https://github.com/bewcloud/bewcloud) - a self-hosted personal cloud platform.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database
- PV provisioner support in the underlying infrastructure

## Installation

```bash
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm dependency update
helm install bewcloud . -f values.yaml
```

## Configuration

This chart inherits from the [bjw-s common library chart](https://github.com/bjw-s/helm-charts/blob/main/charts/library/common/values.yaml).

### Required Secrets

You must configure the following secrets in `values.yaml`:

- **postgres**: Database connection details (host, user, password, dbname, port)
- **jwt**: JWT secret for authentication
- **password**: Password salt for hashing

### Optional Secrets

- **mfa**: Multi-factor authentication settings
- **oidc**: OpenID Connect configuration
- **smtp**: Email server credentials

See `values.yaml` for detailed configuration options and examples.

## Database Migrations

**Important:** Database migrations must be performed manually for now.

Before deploying BewCloud, you need to run migrations against your PostgreSQL database before the application will function correctly. Refer to the [BewCloud documentation](https://github.com/bewcloud/bewcloud) for migration instructions.

## Persistence

By default, the chart provisions a 100Gi PVC for data storage mounted at `/app/data-files`.

## Ingress

Ingress is disabled by default. Enable and configure it in `values.yaml` to expose BewCloud externally.
