output "control_plane_id" {
  value = hcloud_server.control_plane.id
}

output "control_plane_ip" {
  value = hcloud_server.control_plane.ipv4_address
}

output "worker_ips" {
  value = hcloud_server.worker[*].ipv4_address
}

output "k3s_token" {
  value     = local.resolved_k3s_token
  sensitive = true
}
