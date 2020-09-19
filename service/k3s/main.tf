variable "node_count" {}

variable "hostname_format" {
  type = string
}

variable "connections" {
  type = list
}

variable "ssh_key_path" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpn_ips" {
  type    = list
  default = []
}

variable "vpn_interface" {
  type = string
}

variable "private_ips" {
  type    = list
  default = []
}

variable "k3s_version" {
  type = string
}

variable "cluster_cidr_pods" {
  default = "10.42.0.0/16"
}

variable "cluster_cidr_services" {
  default = "10.43.0.0/16"
}

variable "overlay_interface" {
  default = ""
}

variable "kubernetes_interface" {
  default     = ""
  description = "Interface on host that nodes use to communicate with each other. Can be the private interface or wg0 if wireguard is enabled."
}

variable "overlay_cidr" {
  default = "10.42.0.0/16"
}

variable "cni" {
  default = "default"
}

variable "private_interface" {
  default = "eth0"
}

variable "domain" {
  default = "kloud3s.io"
}

variable "drain_timeout" {
  default = "60"
}

variable "loadbalancer" {
  default     = "metallb"
  description = "How LoadBalancer IPs are assigned. Options are metallb(default), traefik, ccm & akrobateo"
}

variable "cni_to_overlay_interface_map" {
  description = "The interface created by the CNI e.g. calico=vxlan.calico, cilium=cilium_vxlan, weave-net=weave, flannel=cni0/flannel.1"
  type        = map
  default = {
    flannel = "cni0"
    weave   = "weave"
    cilium  = "cilium_host"
    calico  = "vxlan.calico"
  }
}

resource "random_string" "token1" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "token2" {
  length  = 16
  upper   = false
  special = false
}

locals {
  cluster_token = "${random_string.token1.result}.${random_string.token2.result}"
  k3s_version   = var.k3s_version == "latest" ? jsondecode(data.http.k3s_version[0].body).tag_name : var.k3s_version
  domain        = var.domain
  cni           = var.cni
  valid_cni     = ["weave", "calico", "cilium", "flannel", "default"]
  validate_cni  = index(local.valid_cni, local.cni)
  loadbalancer  = var.loadbalancer
  # Set overlay interface from map, but optionally allow override
  overlay_interface    = var.overlay_interface == "" ? lookup(var.cni_to_overlay_interface_map, local.cni, "cni0") : var.overlay_interface
  overlay_cidr         = var.overlay_cidr
  private_interface    = var.private_interface
  kubernetes_interface = var.kubernetes_interface == "" ? var.vpn_interface : var.kubernetes_interface

  master_ip         = length(var.vpn_ips) > 0 ? var.vpn_ips[0] : ""
  master_public_ip  = length(var.connections) > 0 ? var.connections[0] : ""
  master_private_ip = length(var.private_ips) > 0 ? var.private_ips[0] : ""
  ssh_key_path      = var.ssh_key_path

  agent_default_flags = [
    "-v 5",
    "--server https://${local.master_ip}:6443",
    "--token ${local.cluster_token}",
    local.cni == "default" ? "--flannel-iface ${local.kubernetes_interface}" : "",
  ]

  agent_install_flags = join(" ", concat(local.agent_default_flags))

  server_default_flags = [
    "-v 5",
    # Explicitly set default flannel interface
    local.cni == "default" ? "--flannel-iface ${local.kubernetes_interface}" : "--flannel-backend=none",
    # Disable network policy
    "--disable-network-policy",
    # Conditonally Disable service load balancer
    local.loadbalancer == "traefik" ? "" : "--disable servicelb",
    # Disable Traefik
    "--disable traefik",
    "--node-ip ${local.master_ip}",
    "--tls-san ${local.master_ip}",
    "--tls-san ${local.master_public_ip}",
    "--tls-san ${local.master_private_ip}",
    "--cluster-cidr ${local.overlay_cidr}",
    "--token ${local.cluster_token}",
    "--kubelet-arg 'network-plugin=cni'",
    "--node-external-ip ${local.master_public_ip}"
  ]

  server_install_flags = join(" ", concat(local.server_default_flags))

}

resource "null_resource" "k3s" {
  count = var.node_count

  triggers = {
    master_public_ip     = local.master_public_ip
    node_public_ip       = element(var.connections, count.index)
    node_name            = format(var.hostname_format, count.index + 1)
    k3s_version          = local.k3s_version
    overlay_cidr         = local.overlay_cidr
    overlay_interface    = local.overlay_interface
    private_interface    = local.private_interface
    kubernetes_interface = local.kubernetes_interface
    server_install_flags = local.server_install_flags
    # Below is used to debug triggers
    # always_run            = "${timestamp()}"
  }

  connection {
    host        = element(var.connections, count.index)
    user        = "root"
    agent       = false
    private_key = file("${var.ssh_key_path}")
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install -qy jq",
      "modprobe br_netfilter && echo br_netfilter >> /etc/modules",
    ]
  }

  # Upload k3s file
  provisioner file {
    content     = data.http.k3s_installer.body
    destination = "/tmp/k3s-installer"
  }

  # Upload manifests
  provisioner file {
    source      = "${path.module}/manifests"
    destination = "/tmp"
  }

  # Upload flannel.yaml for CNI
  provisioner "file" {
    content     = data.template_file.flannel-configuration.rendered
    destination = "/tmp/flannel.yaml"
  }

  # Upload basic certificate issuer
  provisioner "file" {
    content     = data.template_file.basic-cert-issuer.rendered
    destination = "/tmp/basic-cert-issuer.yaml"
  }

  # Upload basic traefik test
  provisioner "file" {
    content     = data.template_file.basic-traefik-test.rendered
    destination = "/tmp/basic-traefik-test.yaml"
  }

  # Upload argocd ingress
  provisioner "file" {
    content     = data.template_file.argocd-ingress.rendered
    destination = "/tmp/argocd-ingress.yaml"
  }

  # Install K3S server
  provisioner "remote-exec" {
    inline = [<<EOT
      %{if count.index == 0~}

        # Download CNI plugins to /opt/cni/bin/ because most CNI's will look in that path
        %{if local.cni != "default"~}
        [ -d "/opt/cni/bin" ] || \
        (wget https://github.com/containernetworking/plugins/releases/download/v0.8.6/cni-plugins-linux-amd64-v0.8.6.tgz && \
        tar zxvf cni-plugins-linux-amd64-v0.8.6.tgz && mkdir -p /opt/cni/bin && mv * /opt/cni/bin/);
        %{endif~}

        echo "[INFO] ---Installing k3s server---";

        INSTALL_K3S_VERSION=${local.k3s_version} sh /tmp/k3s-installer ${local.server_install_flags} \
        --node-name ${self.triggers.node_name};
        until $(nc -z localhost 6443); do echo '[WARN] Waiting for API server to be ready'; sleep 1; done;
        echo "[SUCCESS] API server is ready";
        until $(curl -fk -so nul https://${local.master_ip}:6443/ping); do echo '[WARN] Waiting for master to be ready'; sleep 5; done;

        echo "[SUCCESS] Master is ready";
        echo "[INFO] ---Installing CNI ${local.cni}---";

        %{if local.cni == "flannel"~}
        kubectl apply -f /tmp/flannel.yaml;
        kubectl rollout status ds kube-flannel-ds-amd64 -n kube-system;
        %{endif~}

        echo "[INFO] ---Finished installing CNI ${local.cni}---";

        # Install cert-manager
        kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.1/cert-manager.yaml
        # Wait for cert-manager-webhook to be ready
        kubectl rollout status -n cert-manager deployment cert-manager-webhook --timeout 120s;
        # Install basic cert issuer
        kubectl apply -f /tmp/basic-cert-issuer.yaml;
        # Install traefik
        kubectl apply -f /tmp/manifests/traefik-k3s.yaml;
        # Install basic traefik test
        kubectl apply -f /tmp/basic-traefik-test.yaml;
        # Install helm
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash;
        # Install ArgoCD
        kubectl create ns argocd;
        helm repo add argo https://argoproj.github.io/argo-helm;
        helm install --kubeconfig /etc/rancher/k3s/k3s.yaml -n argocd latest --set server.ingress.enabled=true --set server.extraArgs="{--insecure}" --set configs.secret.argocdServerAdminPassword='$2b$12$/HRbMqfAsEYC.J7uN7S/LeG0GNs4CsdYDTe6lxKpPmTHI60Q/qcUm' argo/argo-cd;
        kubectl apply -f /tmp/argocd-ingress.yaml;

        echo "[INFO] ---Finished installing k3s server---";
      %{else~}
        echo "[INFO] ---Uninstalling k3s---";
        # Clear CNI routes
        k3s-agent-uninstall.sh ; \
        echo "[INFO] ---Uninstalled k3s-server---" || \
        echo "[INFO] ---k3s not found. Skipping...---";

        echo "[INFO] ---Installing k3s agent---";
        # CNI specific commands to run for nodes.
        # It is desirable to wait for networking to complete before proceeding with agent installation

        # Download CNI plugins to /opt/cni/bin/ because most CNI's will look in that path
        %{if local.cni != "default"~}
        [ -d "/opt/cni/bin" ] || \
        (wget https://github.com/containernetworking/plugins/releases/download/v0.8.6/cni-plugins-linux-amd64-v0.8.6.tgz && \
        tar zxvf cni-plugins-linux-amd64-v0.8.6.tgz && mkdir -p /opt/cni/bin && mv * /opt/cni/bin/);
        %{endif~}

        until $(curl -fk -so nul https://${local.master_ip}:6443/ping); do echo '[WARN] Waiting for master to be ready'; sleep 5; done;

        INSTALL_K3S_VERSION=${local.k3s_version} K3S_URL=https://${local.master_ip}:6443 K3S_TOKEN=${local.cluster_token} \
        sh /tmp/k3s-installer ${local.agent_install_flags} --node-ip ${element(var.vpn_ips, count.index)} \
        --node-name ${self.triggers.node_name};
        echo "[INFO] ---Finished installing k3s agent---";
      %{endif~}
    EOT
    ]
  }

}

# Get rid of cyclic errors by storing all required variables to be used in destroy provisioner
resource null_resource k3s_cache {
  count = var.node_count

  triggers = {
    node_name        = format(var.hostname_format, count.index + 1)
    master_public_ip = local.master_public_ip
    ssh_key_path     = var.ssh_key_path
  }
}

# Remove deleted node from cluster
resource null_resource k3s_cleanup {
  count = var.node_count

  triggers = {
    node_init        = null_resource.k3s[count.index].id
    k3s_cache        = null_resource.k3s_cache[count.index].id
    ssh_key_path     = null_resource.k3s_cache[count.index].triggers.ssh_key_path
    master_public_ip = null_resource.k3s_cache[count.index].triggers.master_public_ip
    node_name        = null_resource.k3s_cache[count.index].triggers.node_name
  }


  # Use master(s)
  connection {
    host        = self.triggers.master_public_ip
    user        = "root"
    agent       = false
    private_key = file("${self.triggers.ssh_key_path}")
  }

  # Clean up on deleting node
  provisioner remote-exec {

    when = destroy
    inline = [
      "echo 'Cleaning up ${self.triggers.node_name}...'",
      "kubectl drain ${self.triggers.node_name} --force --delete-local-data --ignore-daemonsets --timeout 180s",
      "kubectl delete node ${self.triggers.node_name}",
      "sed -i \"/${self.triggers.node_name}/d\" /var/lib/rancher/k3s/server/cred/node-passwd",
    ]
  }

}


data "template_file" "flannel-configuration" {
  template = file("${path.module}/templates/flannel.yaml")

  vars = {
    interface    = local.kubernetes_interface
    flannel_cidr = local.overlay_cidr
  }
}

data "template_file" "basic-cert-issuer" {
  template = file("${path.module}/templates/basic-cert-issuer.yaml")

  vars = {
    domain = local.domain
  }
}

data "template_file" "basic-traefik-test" {
  template = file("${path.module}/templates/basic-traefik-test.yaml")

  vars = {
    domain = local.domain
  }
}

data "template_file" "argocd-ingress" {
  template = file("${path.module}/templates/argocd-ingress.yaml")

  vars = {
    domain = local.domain
  }
}

data "http" "k3s_version" {
  count = var.k3s_version == "latest" ? 1 : 0
  url   = "https://api.github.com/repos/rancher/k3s/releases/latest"
}

data "http" "k3s_installer" {
  url = "https://raw.githubusercontent.com/rancher/k3s/master/install.sh"
}

output "overlay_interface" {
  value = local.overlay_interface
}

output "overlay_cidr" {
  value = local.overlay_cidr
}
