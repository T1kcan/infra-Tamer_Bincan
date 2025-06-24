resource "proxmox_vm_qemu" "master" {
  count       = 3
  name        = "k8s-master-0${count.index + 1}"
  target_node = "pve"
  clone       = "ubuntu-cloud"
  full_clone  = true
  os_type     = "cloud-init"
  ciuser      = "cluster"
  cipassword  = "cluster"
  ipconfig0   = "ip=192.168.0.10${count.index + 1}/24,gw=192.168.0.1"
  sshkeys     = ""
  cores       = 2
  memory      = 2048
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }
  disks {
    ide {
      ide3 {
        cloudinit {
          storage = "local"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = "16G"
          storage = "local"
          discard = true
        }
      }
    }
  }
  vga {
    type = "std"
  }
  connection {
    type        = "ssh"
    user        = "cluster"
    private_key = file("./private_key")
    host        = self.ssh_host
    port        = 22

  }
  provisioner "file" {
    source      = "./haproxy.cfg"
    destination = "/tmp/haproxy.cfg"
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 10",
      "sudo apt-get install -y haproxy",
      "sudo cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg",
      "sudo systemctl enable haproxy",
      "sudo systemctl start haproxy"
    ]
  }
}

resource "proxmox_vm_qemu" "worker" {
  count       = 2
  name        = "k8s-worker-0${count.index + 1}"
  target_node = "pve"
  clone       = "ubuntu-cloud"
  full_clone  = true
  os_type     = "cloud-init"
  ciuser      = "cluster"
  cipassword  = "cluster"
  ipconfig0   = "ip=192.168.0.11${count.index + 1}/24,gw=192.168.0.1"
  sshkeys     = ""
  cores       = 2
  memory      = 2048
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }
  disks {
    ide {
      ide3 {
        cloudinit {
          storage = "local"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = "16G"
          storage = "local"
          discard = true
        }
      }
    }
  }
  vga {
    type = "std"
  }
  # connection {
  #   type        = "ssh"
  #   user        = "cluster"
  #   private_key = file("./private_key")
  #   host        = self.ssh_host
  #   port        = 22

  # }

  # provisioner "remote-exec" {
  #   inline = [
  #     "ip a"
  #   ]
  # }
}
