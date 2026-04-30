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
| `GRAFANA_HOST`, `PROMETHEUS_HOST`, `LOKI_HOST` | FQDNs you control for Grafana, Prometheus, and Loki Ingress (e.g. `grafana.mydomain.com`). **Names such as `*.example.com` only work if you own that DNS zone**—otherwise leave empty, use **MONITORING_UI_VIA_LB_IP**, or use port-forward. Empty values skip applying that Ingress. |
| `MONITORING_UI_VIA_LB_IP` | If `true`, deploys `kubernetes/monitoring/monitoring-ui-lb-ip.yaml`, merges `helm/kube-prometheus-stack/values-lb-ip-ui.yaml` (Prometheus `routePrefix` `/prometheus`), and sets Prometheus `externalUrl` to the LB when the address is available. **HTTP (no DNS):** `http://<LB-IP>/` (Grafana), `http://<LB-IP>/prometheus/` (Prometheus UI), `http://<LB-IP>/loki/` (Loki API; Explore still uses the in-cluster datasource). When `false`, the script removes that Ingress. |
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
- **LB IP UI paths:** `helm/kube-prometheus-stack/values-lb-ip-ui.yaml` is merged when `MONITORING_UI_VIA_LB_IP=true` (Prometheus `routePrefix` `/prometheus`). The deploy script then sets `prometheus.prometheusSpec.externalUrl` from the ingress controller’s load balancer address when it is known.
- **Hostname Ingress (default when LB IP mode is off):** `helm/kube-prometheus-stack/values-prometheus-ingress-host.yaml` sets Prometheus `routePrefix` to **`/`** so the Prometheus UI matches `kubernetes/monitoring/prometheus-ingress.yaml`. When **`PROMETHEUS_HOST`** is set and **`MONITORING_UI_VIA_LB_IP`** is false, the script sets **`externalUrl`** to **`https://${PROMETHEUS_HOST}/`**.
- **Persistent mode:** set `MONITORING_USE_EPHEMERAL_STORAGE=false` and ensure StorageClasses and CSI work so PVCs for Grafana, Prometheus, and Loki can bind.

## DNS and TLS

1. **Automated (Cloudflare):** Set `ENABLE_EXTERNAL_DNS=true`, `EXTERNAL_DNS_PROVIDER=cloudflare`, `EXTERNAL_DNS_DOMAIN_FILTER`, and `CF_API_TOKEN`. Recreate records by re-running `deploy-monitoring.sh` after changing Ingress hostnames. Ensure the zone’s nameservers point at Cloudflare.
2. **Manual:** Create `A` or `AAAA` records for `GRAFANA_HOST` / `PROMETHEUS_HOST` / `LOKI_HOST` to the **external IP** of `ingress-nginx-controller` in `monitoring`: `kubectl -n monitoring get svc ingress-nginx-controller`.
3. **No DNS:** Use `MONITORING_UI_VIA_LB_IP=true` for Grafana, Prometheus, and the Loki API path on the **same** load balancer IP, or `kubectl port-forward` (see below).

For HTTPS with Let’s Encrypt, set `ENABLE_CERT_MANAGER=true`, valid hostnames, and DNS that resolves to the load balancer before certificates can succeed.

### Moving from LB IP only to your own domain

You can start with **`MONITORING_UI_VIA_LB_IP=true`** (HTTP on the load balancer IP) and later switch to hostnames:

1. Create **A/AAAA** (or ExternalDNS) records for your new names pointing to the **same** ingress load balancer address as before.
2. In `.env`, set **`GRAFANA_HOST`**, **`PROMETHEUS_HOST`**, and **`LOKI_HOST`** to those FQDNs, set **`MONITORING_UI_VIA_LB_IP=false`**, enable **`ENABLE_CERT_MANAGER`** if you want TLS, and run **`./scripts/deploy-monitoring.sh`** again.

The script removes the combined IP Ingress, applies the per-host Ingress manifests, resets Prometheus **`routePrefix`** to **`/`** (not `/prometheus`), and sets **`prometheus.prometheusSpec.externalUrl`** to **`https://${PROMETHEUS_HOST}/`** when **`PROMETHEUS_HOST`** is set.

## Grafana and UI access

| Method | When to use |
| ------ | ----------- |
| **Ingress hostname** | Set `GRAFANA_HOST` to a name that resolves to the LB; optional TLS via cert-manager. URL: `https://$GRAFANA_HOST` |
| **HTTP via LB IP** | `MONITORING_UI_VIA_LB_IP=true` → `EXTERNAL-IP` from `kubectl -n monitoring get svc ingress-nginx-controller` — Grafana `http://<IP>/`, Prometheus `http://<IP>/prometheus/`, Loki API `http://<IP>/loki/` |
| **Port-forward** | No ingress/DNS: e.g. `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` → `http://localhost:3000` |

Credentials: user **`admin`**, password from **`GRAFANA_ADMIN_PASSWORD`** (or **`admin`** if unset).

**Without the LB IP Ingress**, port-forward Prometheus / Loki:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n monitoring port-forward svc/loki 3100:3100
```

Then open `http://localhost:9090` and `http://localhost:3100`.

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
- **Hostnames:** Do not set `GRAFANA_HOST` / `PROMETHEUS_HOST` / `LOKI_HOST` to `*.example.com` unless you control that domain; use your own FQDNs and DNS, LB IP mode for Grafana, or port-forward.

## Troubleshooting

- Nodes not ready: `kubectl get nodes -o wide`; on the node, `journalctl -u k3s`.
- Grafana not reachable: confirm DNS or `MONITORING_UI_VIA_LB_IP`; `kubectl -n monitoring get ingress,svc`.
- PVCs pending: check CSI pods and StorageClass; temporarily use `MONITORING_USE_EPHEMERAL_STORAGE=true`.
- Promtail: `kubectl -n monitoring logs ds/promtail`.
- Prometheus remote write: check `PROMETHEUS_HOST`, ingress, and TLS.
- Ingress admission errors (`validate.nginx.ingress.kubernetes.io` timeouts): see **Operational notes** above.
- **`SyncLoadBalancerFailed` / `providerID does not have one of the expected prefixes … k3s://…`:** The Hetzner CCM needs **`spec.providerID=hcloud://<server-id>`** on each node. Current cloud-init replaces the default **`k3s://`** ID using the [Hetzner metadata](https://docs.hetzner.com/cloud/servers/metadata/) `instance-id`. **New clusters:** `terraform apply` (replace nodes) with updated `terraform/cloud-init/*.tftpl`, or rebuild workers/control plane. **Existing cluster without replacing VMs:** for each node, get the numeric server id in the Hetzner console (or API), then e.g. `kubectl patch node <name> -p '{"spec":{"providerID":"hcloud://<id>"}}' --type=merge` and restart `k3s` on that node if the field does not stick; confirm with `kubectl get node <name> -o jsonpath='{.spec.providerID}'`.

## Observability Standards

See `docs/observability-standards.md` for metric naming, labels, log format, and alert severity conventions.

## Assumptions

- Single dedicated monitoring cluster per environment (or shared with clear `cluster` label segregation).
- DNS either points at the Hetzner ingress load balancer (manually, via ExternalDNS/Cloudflare, or via `/etc/hosts` for testing), or you use LB IP / port-forward access.
- `hcloud-cloud-controller-manager` credentials are available where the CCM expects them during control-plane bootstrap.
- Loki defaults to single-binary filesystem mode for bootstrap; object storage is recommended for large-scale retention.
