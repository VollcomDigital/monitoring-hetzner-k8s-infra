resource "hcloud_network" "cluster" {
  name     = "${var.cluster_name}-network"
  ip_range = var.network_cidr

  labels = merge(var.labels, {
    cluster = var.cluster_name
  })
}

resource "hcloud_network_subnet" "cluster" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_cidr
}
