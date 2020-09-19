/* general */
variable "node_count" {
  default = 3
}

variable "domain" {
  default = "kloud3s.io"
}

variable "hostname_format" {
  default = "kube%d"
}

variable "ssh_key_path" {
  default = "./.ssh/tf-kube"
}

variable "ssh_pubkey_path" {
  default = "./.ssh/tf-kube.pub"
}

variable "ssh_keys_dir" {
  default = "./.ssh"
}

variable "k3s_version" {
  default = "latest"
}

variable "kubeconfig_path" {
  default = "./.ssh/kubeconfig"
}

variable "create_zone" {
  default = false
}

variable "cni" {
  default     = "cilium"
  description = "Choice of CNI to install e.g. flannel, weave, cilium, calico"
}

variable "overlay_cidr" {
  default     = "10.42.0.0/16"
  description = "Cluster cidr"
}

/* ovh */
variable "tenant_name" {
  type        = string
  description = "The Name of the Tenant (Identity v2) or Project (Identity v3) to login with"
}

variable "user_name" {
  type        = string
  description = "The Username to login with"
}

variable "password" {
  type        = string
  description = "The Password to login with"
}

variable "auth_url" {
  default     = "https://auth.cloud.ovh.net/v3"
  description = "The Identity authentication URL"
}

variable "application_key" {
  type        = string
  description = "The API Application Key"
  default     = ""
}

variable "application_secret" {
  type        = string
  description = "The API Application Secret"
  default     = ""
}

variable "consumer_key" {
  type        = string
  description = "The API Consumer key"
  default     = ""
}

variable "endpoint" {
  default     = "ovh-ca"
  description = "The API endpoint to use"
}

variable "ovh_ssh_keys" {
  type    = list(string)
  default = [""]
}

variable "region" {
  default     = "BHS5"
  description = "The region of the OpenStack cloud to use"
}

variable "ovh_type" {
  default     = "s1-2"
  description = "Server type e.g. s1-2, s1-4, s1-8"
}

variable "ovh_image" {
  default = "Ubuntu 20.04"
}

/* digitalocean */
variable "digitalocean_token" {
  default = ""
}
