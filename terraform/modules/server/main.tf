resource "hcloud_ssh_key" "cluster" {
  name       = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
  labels     = var.labels
}

resource "random_password" "k3s_token" {
  count   = var.k3s_token == "" ? 1 : 0
  length  = 48
  special = false
}

locals {
  resolved_k3s_token = var.k3s_token != "" ? var.k3s_token : random_password.k3s_token[0].result
}

resource "hcloud_server" "control_plane" {
  name        = "${var.cluster_name}-cp-0"
  server_type = var.control_plane_server_type
  image       = var.control_plane_image
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.cluster.id]
  firewall_ids = [
    var.control_plane_firewall_id
  ]

  labels = merge(var.labels, {
    role = "control-plane"
  })

  user_data = templatefile(var.cloud_init_control_plane_path, {
    k3s_version     = var.k3s_version
    k3s_token       = local.resolved_k3s_token
    is_first_server = true
    api_server_lb   = var.api_server_lb_ip
    node_name       = "${var.cluster_name}-cp-0"
    cluster_name    = var.cluster_name
    pod_cidr        = var.pod_cidr
    service_cidr    = var.service_cidr
    cluster_dns     = var.cluster_dns
    hcloud_token    = var.hcloud_token
  })

  network {
    network_id = var.network_id
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  depends_on = [var.subnet_id]
}

resource "hcloud_server" "worker" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index}"
  server_type = var.worker_server_type
  image       = var.worker_image
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.cluster.id]
  firewall_ids = [
    var.worker_firewall_id
  ]

  labels = merge(var.labels, {
    role = "worker"
  })

  user_data = templatefile(var.cloud_init_worker_path, {
    k3s_version   = var.k3s_version
    k3s_token     = local.resolved_k3s_token
    api_server_lb = var.api_server_lb_ip
    node_name     = "${var.cluster_name}-worker-${count.index}"
  })

  network {
    network_id = var.network_id
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  depends_on = [hcloud_server.control_plane]
}
