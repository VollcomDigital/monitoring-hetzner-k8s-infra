# monitoring-hetzner-k8s-boilerplate

Production-ready, reusable boilerplate for a dedicated Kubernetes monitoring platform on Hetzner Cloud using Terraform, k3s, and Helm.

## What This Repository Provides

- Hetzner infrastructure provisioning (network, firewall, control plane, workers, API load balancer)
- k3s cluster bootstrap through cloud-init
- Monitoring stack in `monitoring` namespace:
  - `kube-prometheus-stack` (Prometheus, Grafana, Alertmanager)
  - `loki`
  - `promtail`
- NGINX ingress controller by default
- cert-manager + Let's Encrypt integration prepared and optional
- Grafana dashboards auto-imported via ConfigMaps
- Cross-cluster examples for Prometheus `remote_write` and Promtail log shipping

## Repository Structure

```text
monitoring-hetzner-k8s-boilerplate/
├── terraform/
├── kubernetes/
├── helm/
├── monitoring/
│   ├── grafana/
│   │   └── dashboards/
│   ├── prometheus/
│   │   └── rules/
│   ├── loki/
│   └── alertmanager/
├── examples/
│   └── prod-cluster/
├── scripts/
├── docs/
└── README.md
```

## Prerequisites

- Terraform >= 1.5
- kubectl
- Helm >= 3
- SSH key pair available locally
- Hetzner Cloud API token

## Setup

```bash
cp .env.example .env
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Update:

- `.env` (`HCLOUD_TOKEN`, hostnames, optional cert-manager settings)
- `terraform/terraform.tfvars` (cluster sizing and region)

## Required Workflow

```bash
# 1) Provision infrastructure + k3s
cd terraform
terraform init
terraform apply
cd ..

# 2) Deploy monitoring platform
./scripts/deploy-monitoring.sh
```

Equivalent helper for provisioning:

```bash
./scripts/provision.sh
```

## Grafana Access

After deployment:

- URL: `https://$GRAFANA_HOST`
- User: `admin`
- Password: `GRAFANA_ADMIN_PASSWORD` from `.env` (or `admin` if unset)

If no DNS/ingress is available yet:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Then open `http://localhost:3000`.

## Cross-Cluster Monitoring

Example configs are in `examples/prod-cluster/`:

- `prometheus-remote-write.yaml` for sending metrics from a production cluster to this monitoring cluster
- `promtail-loki-client.yaml` for shipping production logs to this monitoring cluster

Set:

- `PROMETHEUS_HOST` to your monitoring-cluster Prometheus ingress host
- `LOKI_HOST` to your monitoring-cluster Loki ingress host

Then apply equivalent settings on each external cluster.

## cert-manager and Let's Encrypt

Prepared but optional by default.

In `.env`:

- set `ENABLE_CERT_MANAGER=true`
- set `ACME_EMAIL`
- choose issuer in `LETSENCRYPT_ISSUER` (`letsencrypt-staging` or `letsencrypt-production`)

`deploy-monitoring.sh` installs cert-manager and applies ClusterIssuers from `kubernetes/cert-manager/cluster-issuers.yaml`.

## Troubleshooting

- Nodes not ready:
  - `kubectl get nodes -o wide`
  - check cloud-init on node: `journalctl -u k3s`
- Grafana ingress not reachable:
  - verify DNS points to ingress load balancer IP
  - `kubectl -n monitoring get ingress,svc`
- Promtail not shipping logs:
  - `kubectl -n monitoring logs ds/promtail`
- Prometheus remote write failing:
  - verify `PROMETHEUS_HOST` ingress and TLS certificate

## Observability Standards

See `docs/observability-standards.md` for metric naming, labels, log format, and alert severity conventions.

## Assumptions

- Single dedicated monitoring cluster per environment (or shared with clear `cluster` label segregation).
- Ingress DNS records are managed externally and point to Hetzner load balancer IP.
- `hcloud-cloud-controller-manager` secret is created during control-plane bootstrap.
- Loki defaults to single-binary filesystem mode for minimal production bootstrap; object storage migration is recommended for long-term retention at scale.
