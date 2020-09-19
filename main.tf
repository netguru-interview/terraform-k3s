module "ssh" {
  source          = "./ssh"
  ssh_key_path    = var.ssh_key_path
  ssh_pubkey_path = var.ssh_pubkey_path
  ssh_keys_dir    = var.ssh_keys_dir
}

module "provider" {
  source = "./provider/ovh"

  application_key    = var.application_key
  application_secret = var.application_secret
  consumer_key       = var.consumer_key
  endpoint           = var.endpoint
  region             = var.region
  tenant_name        = var.tenant_name
  user_name          = var.user_name
  password           = var.password
  auth_url           = var.auth_url
  ssh_keys           = var.ovh_ssh_keys
  size               = var.ovh_type
  image              = var.ovh_image
  hosts              = var.node_count
  hostname_format    = var.hostname_format
  ssh_key_path       = module.ssh.private_key
  ssh_pubkey_path    = module.ssh.public_key
}

module "swap" {
  source = "./service/swap"

  node_count   = var.node_count
  connections  = module.provider.public_ips
  ssh_key_path = module.ssh.private_key
}

module "dns" {
  source = "./dns/digitalocean"

  node_count  = var.node_count
  token       = var.digitalocean_token
  domain      = var.domain
  public_ips  = module.provider.public_ips
  hostnames   = module.provider.hostnames
  create_zone = var.create_zone
}

module "wireguard" {
  source = "./security/wireguard"

  node_count   = var.node_count
  connections  = module.provider.public_ips
  private_ips  = module.provider.private_ips
  hostnames    = module.provider.hostnames
  overlay_cidr = module.k3s.overlay_cidr
  ssh_key_path = module.ssh.private_key
}

module "firewall" {
  source = "./security/ufw"

  node_count        = var.node_count
  connections       = module.provider.public_ips
  private_interface = module.provider.private_network_interface
  vpn_interface     = module.wireguard.vpn_interface
  vpn_port          = module.wireguard.vpn_port
  overlay_interface = module.k3s.overlay_interface
  overlay_cidr      = module.k3s.overlay_cidr
  ssh_key_path      = module.ssh.private_key
}

module "k3s" {
  source = "./service/k3s"

  node_count        = var.node_count
  connections       = module.provider.public_ips
  cluster_name      = var.domain
  vpn_interface     = module.wireguard.vpn_interface
  vpn_ips           = module.wireguard.vpn_ips
  hostname_format   = var.hostname_format
  ssh_key_path      = module.ssh.private_key
  k3s_version       = var.k3s_version
  cni               = var.cni
  overlay_cidr      = var.overlay_cidr
  kubeconfig_path   = var.kubeconfig_path
  private_ips       = module.provider.private_ips
  private_interface = module.provider.private_network_interface
  domain            = var.domain
}

output "private_key" {
  value = abspath(module.ssh.private_key)
}

output "public_key" {
  value = abspath(module.ssh.public_key)
}

output "ssh-master" {
  value = "ssh -i ${abspath(module.ssh.private_key)} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${try(module.provider.public_ips[0], "localhost")}"
}

output "instances" {
  value = module.provider.nodes
}

output "kubeconfig" {
  value = module.k3s.kubeconfig
}
