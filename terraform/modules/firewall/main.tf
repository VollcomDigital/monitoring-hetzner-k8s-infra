resource "hcloud_firewall" "control_plane" {
  name = "${var.cluster_name}-control-plane"

  labels = merge(var.labels, {
    cluster = var.cluster_name
    role    = "control-plane"
  })

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.api_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9345"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2379-2380"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [var.network_cidr]
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall" "worker" {
  name = "${var.cluster_name}-worker"

  labels = merge(var.labels, {
    cluster = var.cluster_name
    role    = "worker"
  })

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}
