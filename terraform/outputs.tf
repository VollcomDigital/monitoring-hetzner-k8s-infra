output "cluster_name" {
  description = "Cluster name"
  value       = var.cluster_name
}

output "region" {
  description = "Hetzner region used for deployment"
  value       = var.region
}

output "api_server_url" {
  description = "Kubernetes API URL via Hetzner Load Balancer"
  value       = "https://${hcloud_load_balancer.api.ipv4}:6443"
}

output "kubeconfig_path" {
  description = "Path to generated kubeconfig file"
  value       = abspath("${path.module}/../kubeconfig.yaml")
}

output "control_plane_ip" {
  description = "Public IPv4 address of control-plane node"
  value       = module.servers.control_plane_ip
}

output "worker_ips" {
  description = "Public IPv4 addresses of worker nodes"
  value       = module.servers.worker_ips
}
