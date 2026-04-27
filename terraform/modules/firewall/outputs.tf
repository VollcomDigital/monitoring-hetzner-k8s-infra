output "control_plane_firewall_id" {
  value = hcloud_firewall.control_plane.id
}

output "worker_firewall_id" {
  value = hcloud_firewall.worker.id
}
