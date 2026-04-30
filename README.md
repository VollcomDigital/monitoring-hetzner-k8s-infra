# monitoring-hetzner-k8s-boilerplate

Production-ready, reusable boilerplate for a dedicated Kubernetes monitoring platform on Hetzner Cloud using Terraform, k3s, and Helm.

## What This Repository Provides

- Hetzner infrastructure provisioning (network, firewall, control plane, workers, API load balancer)
- k3s cluster bootstrap through cloud-init
- **Core cluster addons** applied before Helm: Hetzner Cloud Controller Manager and CSI driver (`kubernetes/core/`), including StorageClasses for network-attached volumes (`hcloud-network-volumes`, `hcloud-network-volumes-immediate`)
- Monitoring stack in the `monitoring` namespace:
  - **kube-prometheus-stack** (Prometheus, Grafana, Alertmanager)
  - **Loki** (single-binary; optional ephemeral storage when CSI/PVCs are not ready)
  - **Promtail**
- **ingress-nginx** as the ingress controller (Hetzner Load Balancer annotations in values)
- **Optional cert-manager** + Let’s Encrypt ClusterIssuers
- **Optional ExternalDNS** with **Cloudflare** (automatic DNS records for Ingress hostnames)
- **Optional Grafana over HTTP on the load balancer IP** when DNS is not available (`MONITORING_UI_VIA_LB_IP`)
- Grafana dashboards auto-imported via ConfigMaps; Prometheus rules included
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

Edit `.env` for deploy behavior and hostnames, and `terraform/terraform.tfvars` for cluster sizing and region. See **Configuration** below.

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

**Kubeconfig:** Terraform writes `kubeconfig.yaml` at the repository root by default. `deploy-monitoring.sh` uses `KUBECONFIG` from `.env` (default `./kubeconfig.yaml`).

## Configuration (`.env`)

| Variable | Purpose |
| -------- | ------- |
| `HCLOUD_TOKEN` | Hetzner Cloud API token (required for Terraform / `./scripts/provision.sh`). |
| `HCLOUD_REGION` | Hetzner location for LB annotations (default `nbg1`). |
| `KUBECONFIG` | Path to kubeconfig (default `./kubeconfig.yaml`). |
| `MONITORING_USE_EPHEMERAL_STORAGE` | If `true`, Grafana/Prometheus/Loki use emptyDir-style storage via extra Helm values so the stack installs without waiting on PVC binding (default `true`). Set `false` when CSI volumes bind and you want durable TSDB, Grafana, and Loki data on disks. |
| `GRAFANA_HOST`, `PROMETHEUS_HOST`, `LOKI_HOST` | Hostnames for name-based Ingress objects. **Placeholder names like `*.example.com` do not point at your cluster** until you create DNS (or use ExternalDNS / `/etc/hosts`). Leave empty to skip applying those Ingress manifests. |
| `MONITORING_UI_VIA_LB_IP` | If `true`, deploys `kubernetes/monitoring/grafana-ingress-ip.yaml` so Grafana is reachable at **`http://<ingress-load-balancer-IP>/`** (HTTP, no DNS). |
| `ENABLE_EXTERNAL_DNS` | If `true`, installs **external-dns** (Cloudflare) into `monitoring` using `helm/external-dns/values-cloudflare.yaml`. Requires `EXTERNAL_DNS_DOMAIN_FILTER` and `CF_API_TOKEN`. |
| `EXTERNAL_DNS_PROVIDER` | Only **`cloudflare`** is automated by `deploy-monitoring.sh`. **Hetzner DNS** is not a built-in upstream provider; use Cloudflare here, manage records manually, or add a separate webhook-based setup. |
| `EXTERNAL_DNS_DOMAIN_FILTER` | DNS zone name managed in Cloudflare (e.g. `mydomain.com`). |
| `CF_API_TOKEN` | Cloudflare API token (Zone: DNS Edit, Zone: Read as needed). |
| `ENABLE_CERT_MANAGER` | If `true`, installs cert-manager and applies ClusterIssuers; requires `ACME_EMAIL`. |
| `LETSENCRYPT_ISSUER` | ClusterIssuer name reference for Ingress TLS (`letsencrypt-staging` or `letsencrypt-production`). |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password (defaults to `admin` if unset). |

Optional informational aliases (not read by the deploy script unless you extend it): `DNS_PROVIDER`, `HETZNER_DNS_TOKEN` in `.env.example` for alignment with other boilerplates.

## Storage and Helm overlays

- **Ephemeral mode:** `helm/kube-prometheus-stack/values-ephemeral.yaml` and `helm/loki/values-ephemeral.yaml` are merged when `MONITORING_USE_EPHEMERAL_STORAGE=true`.
- **Persistent mode:** set `MONITORING_USE_EPHEMERAL_STORAGE=false` and ensure StorageClasses and CSI work so PVCs for Grafana, Prometheus, and Loki can bind.

## DNS and TLS

1. **Automated (Cloudflare):** Set `ENABLE_EXTERNAL_DNS=true`, `EXTERNAL_DNS_PROVIDER=cloudflare`, `EXTERNAL_DNS_DOMAIN_FILTER`, and `CF_API_TOKEN`. Recreate records by re-running `deploy-monitoring.sh` after changing Ingress hostnames. Ensure the zone’s nameservers point at Cloudflare.
2. **Manual:** Create `A` or `AAAA` records for `GRAFANA_HOST` / `PROMETHEUS_HOST` / `LOKI_HOST` to the **external IP** of `ingress-nginx-controller` in `monitoring`: `kubectl -n monitoring get svc ingress-nginx-controller`.
3. **No DNS:** Use `MONITORING_UI_VIA_LB_IP=true` for Grafana on the LB IP, or `kubectl port-forward` (see below).

For HTTPS with Let’s Encrypt, set `ENABLE_CERT_MANAGER=true`, valid hostnames, and DNS that resolves to the load balancer before certificates can succeed.

## Grafana and UI access

| Method | When to use |
| ------ | ----------- |
| **Ingress hostname** | Set `GRAFANA_HOST` to a name that resolves to the LB; optional TLS via cert-manager. URL: `https://$GRAFANA_HOST` |
| **HTTP via LB IP** | `MONITORING_UI_VIA_LB_IP=true` → `http://<EXTERNAL-IP>/` (from `kubectl -n monitoring get svc ingress-nginx-controller`) |
| **Port-forward** | No ingress/DNS: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` → `http://localhost:3000` |

Credentials: user **`admin`**, password from **`GRAFANA_ADMIN_PASSWORD`** (or **`admin`** if unset).

**Prometheus / Loki UIs without DNS:** Port-forward the services, for example:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n monitoring port-forward svc/loki 3100:3100
```

## Cross-Cluster Monitoring

Example configs are in `examples/prod-cluster/`:

- `prometheus-remote-write.yaml` for sending metrics from a production cluster to this monitoring cluster
- `promtail-loki-client.yaml` for shipping production logs to this monitoring cluster

Set `PROMETHEUS_HOST` and `LOKI_HOST` on this cluster to the hostnames you expose, then apply equivalent settings on each external cluster.

## cert-manager and Let’s Encrypt

Disabled by default. To enable:

- `ENABLE_CERT_MANAGER=true`
- `ACME_EMAIL` set
- `LETSENCRYPT_ISSUER` set to `letsencrypt-staging` or `letsencrypt-production`

`deploy-monitoring.sh` installs cert-manager and applies `kubernetes/cert-manager/cluster-issuers.yaml`. The script includes rollout waits and retries for webhook timing issues on some clusters.

## Operational notes

- **ingress-nginx:** Validating admission webhooks may be disabled in `helm/nginx-ingress/values.yaml` when the API server cannot reach in-cluster admission endpoints (common on some control-plane setups). Ingress resources still work; only admission-time validation is skipped.
- **Placeholders:** Do not rely on default `*.example.com` hostnames until DNS exists or you use LB IP / port-forward.

## Troubleshooting

- Nodes not ready: `kubectl get nodes -o wide`; on the node, `journalctl -u k3s`.
- Grafana not reachable: confirm DNS or `MONITORING_UI_VIA_LB_IP`; `kubectl -n monitoring get ingress,svc`.
- PVCs pending: check CSI pods and StorageClass; temporarily use `MONITORING_USE_EPHEMERAL_STORAGE=true`.
- Promtail: `kubectl -n monitoring logs ds/promtail`.
- Prometheus remote write: check `PROMETHEUS_HOST`, ingress, and TLS.
- Ingress admission errors (`validate.nginx.ingress.kubernetes.io` timeouts): see **Operational notes** above.

## Observability Standards

See `docs/observability-standards.md` for metric naming, labels, log format, and alert severity conventions.

## Assumptions

- Single dedicated monitoring cluster per environment (or shared with clear `cluster` label segregation).
- DNS either points at the Hetzner ingress load balancer (manually, via ExternalDNS/Cloudflare, or via `/etc/hosts` for testing), or you use LB IP / port-forward access.
- `hcloud-cloud-controller-manager` credentials are available where the CCM expects them during control-plane bootstrap.
- Loki defaults to single-binary filesystem mode for bootstrap; object storage is recommended for large-scale retention.
