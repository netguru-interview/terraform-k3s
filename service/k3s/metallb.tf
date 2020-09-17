resource "null_resource" "metallb_install" {
  count = var.node_count > 0 ? 1 : 0
  triggers = {
    ssh_key_path     = local.ssh_key_path
    master_public_ip = local.master_public_ip
    k3s_id           = join(" ", null_resource.k3s.*.id)
  }

  depends_on = [null_resource.k3s]

  # Use master(s)
  connection {
    host        = self.triggers.master_public_ip
    user        = "root"
    agent       = false
    private_key = file("${self.triggers.ssh_key_path}")
  }

  # Upload metallb.yaml for assigning loadbalancer IP
  provisioner file {
    source      = "${path.module}/manifests/metallb.yaml"
    destination = "/tmp/metallb.yaml"
  }

  # Install metallb
  provisioner "remote-exec" {
    inline = [<<EOT
      until $(nc -z localhost 6443); do echo '[WARN] Waiting for API server to be ready'; sleep 1; done;
      until kubectl apply -f /tmp/metallb.yaml; do nc -zvv localhost 6443; sleep 5; done;
    EOT
    ]
  }
}


locals {
  metallb_config = templatefile("${path.module}/templates/metallb_config.yaml", {
    master_public_ip = local.master_public_ip
  })
}

resource "null_resource" "metallb_apply" {
  count = var.node_count > 0 && local.loadbalancer == "metallb" ? 1 : 0
  triggers = {
    metallb          = join(" ", null_resource.metallb_install.*.id)
    metallb_config   = md5(local.metallb_config)
    ssh_key_path     = local.ssh_key_path
    master_public_ip = local.master_public_ip
  }

  # Use master(s)
  connection {
    host        = self.triggers.master_public_ip
    user        = "root"
    agent       = false
    private_key = file("${self.triggers.ssh_key_path}")
  }

  # Upload metallb_config.yaml
  provisioner file {
    content     = local.metallb_config
    destination = "/tmp/metallb_config.yaml"
  }

  # Start metallb
  provisioner "remote-exec" {
    inline = [<<EOT
      kubectl apply -f /tmp/metallb_config.yaml;
      # Required to reload config if IPs change
      # https://github.com/metallb/metallb/issues/462
      kubectl -n=metallb-system delete po -l=component=controller;
    EOT
    ]
  }
}
