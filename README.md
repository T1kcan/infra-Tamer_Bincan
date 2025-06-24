# Provision Kubernetes Nodes via Terraform on Proxmox Server
Install Proxmox on a bare metal hardware.
# Create User, Role and Token for Terraform on Proxmox Server:
```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve --password password

pveum aclmod / -user terraform-prov@pve -role TerraformProv

pveum role modify TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"

pveum user token add terraform-prov@pve mytoken
```
- Take notes of your crendentials
```text
terraform-prov@pve!mytoken
xxxx-xxxx-xxxx-xxxx
# use single quotes for the API token ID because of the exclamation mark
export PM_API_TOKEN_ID='terraform-prov@pve!mytoken'
export PM_API_TOKEN_SECRET="xxxx-xxxx-xxxx-xxxx"
export PM_USER="terraform-prov@pve"
export PM_PASS="password"
```
- Create Cloud Teplate:
Use following cloud image to create ubuntu 24.04 VM template:
https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

- Give following commands on Proxmox Server to create cloud template:
```bash
qm create 9004 --memory 2048 --name ubuntu-cloud --net0 virtio,bridge=vmbr0
cd /var/lib/vz/template/iso/
qm importdisk 9004 noble-server-cloudimg-amd64.img local
qm set 9004 --scsihw virtio-scsi-pci --scsi0 local:9004/vm-9004-disk-0.raw
qm set 9004 --ide2 local:cloudinit
cd
qm set 9004 --ciuser cluster --cipassword cluster --sshkey /root/id_rsa.pub --ipconfig0 ip=dhcp,gw=192.168.0.1
qm set 9004 --boot c --bootdisk scsi0
qm set 9004 --serial0 socket --vga serial0
qm template 9004
qm cloudinit dump 120 [user|network|meta]
```
Depending of your hw following changes can be made:
```Text
Notes:
- balooning of memory
- change cpu type to host and numa enable
- hdd sdd emualation`
```
Some additional commands to know:
```bash
- qm disk resize 199 scsi0 10G
- lvresize -l +100%FREE /dev/pve/root
- resize2fs /dev/mapper/pve-root
```

# Create a VM for deployment purposes:

- Install `terraform` on deploy node:
```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
command -v terraform
mkdir terraform 
cd terraform
vim main.tf
#create infra contents
```

## Create VMs
- Clone Repo and create Kubernetes Control and Worker nodes via terraform on Proxmox with following commands:
```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply --auto-approve
```

# Deploy Kubernetes via Kubespray

- Edit /etc/hosts file to add the IP addresses and hostnames of your Kubernetes cluster nodes. This is necessary for the nodes to resolve each other's hostnames correctly.
```bash
sudo vi /etc/hosts
192.168.0.101 control1
192.168.0.102 control2
192.168.0.103 control3
192.168.0.111 worker1
192.168.0.112 worker2
192.168.0.30 deploy
```
- Generate SSH keys and copy them to the each worker and control nodes to enable passwordless SSH access
```bash
ssh-keygen -t rsa 
ssh-copy-id worker1
...
```
- Set the hostname for the control node and configure sudoers to allow passwordless sudo access
- Install necessary packages like vim and configure sudoers file
```bash
sudo apt install vim
sudo vi /etc/sudoers
```
- or edit with visudo:
```bash
sudo hostnamectl set-hostname control1
sudo visudo
%sudo ALL=(ALL) NOPASSWD:ALL
```

## Kubespray
- Clone Kubespray Repository:
```bash
sudo apt install git -y
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
```
Note: Ansible playbook requires ping utils present on each machine, thence install the packet if necessary.
```bash
sudo apt-get install -y iputils-ping
```
Note: Ansible playbook uses root account as become user by default thence make sure public key present on each nodes' /root/.ssh/authorized_keys file:
```bash
ssh worker1
sudo cp /home/cluster/.ssh/authorized_keys /root/.ssh/authorized_keys
sudo cat /root/.ssh/authorized_keys
```
## Install Docker for running Kubespray:
### Add Docker's official GPG key:
```bash
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
# Add the repository to Apt sources:
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run hello-world                                                
sudo usermod -aG docker $USER
sudo usermod -aG docker cluster
newgrp docker
docker run hello-world
```
## Create/Edit Invertory File

~/kubespray/inventory/sample/inventory.ini
```ini
# This inventory describe a HA typology with stacked etcd (== same nodes as control plane)
# and 3 worker nodes
# See https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html
# for tips on building your # inventory

# Configure 'ip' variable to bind kubernetes services on a different ip than the default iface
# We should set etcd_member_name for etcd cluster. The node that are not etcd members do not need to set the value,
# or can set the empty string value.
[kube_control_plane]
node1 ansible_host=192.168.0.101  # ip=10.3.0.1 etcd_member_name=etcd1
node2 ansible_host=192.168.0.102  # ip=10.3.0.2 etcd_member_name=etcd2
node3 ansible_host=192.168.0.103  # ip=10.3.0.3 etcd_member_name=etcd3

[etcd:children]
kube_control_plane

[kube_node]
node4 ansible_host=192.168.0.111  # ip=10.3.0.4
node5 ansible_host=192.168.0.112  # ip=10.3.0.5
# node6 ansible_host=95.54.0.17  # ip=10.3.0.6
```
## Run Kubespray
```bash
docker run --rm -it --mount type=bind,source="$(pwd)"/inventory/sample,dst=/inventory \
  --mount type=bind,source="${HOME}"/.ssh/id_rsa,dst=/root/.ssh/id_rsa \
  quay.io/kubespray/kubespray:v2.28.0 bash

# Enable loadbalancer settings on all.yaml
vi inventory/local/group_vars/all/all.yml
## Internal loadbalancers for apiservers
loadbalancer_apiserver_localhost: true
# valid options are "nginx" or "haproxy"
loadbalancer_apiserver_type: haproxy # valid values "nginx" or "haproxy"

# Inside the container you may now run the kubespray playbooks:
ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_rsa cluster.yml
```

## Install kubectl
- On deploy node install kubectl to gather cluster information:
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```
## Gather Cluster Config
```bash
ssh control1 sudo cp /etc/kubernetes/admin.conf /home/cluster/config
ssh control1 sudo chmod +r ~/config
scp control1:~/config .
mkdir .kube
mv config .kube
```
## NFS Server Setup:
```bash
sudo apt install nfs-server
sudo mkdir /nfs
sudo chmod -R 755 /nfs
sudo chown nfsnobody:nfsnobody /nfs
sudo nano /etc/exports
sudo systemctl restart nfs-server

sudo nano /etc/exports
--------------
/nfs *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure)
--------------
sudo systemctl restart nfs-server
--------------
firewall-cmd --permanent --zone=public --add-service=nfs
firewall-cmd --permanent --zone=public --add-service=mountd
firewall-cmd --permanent --zone=public --add-service=rpc-bind
firewall-cmd --reload
```
## Helm Installation:
```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

## NFS Provisioner:
- Install required linux components to use NFS drive for each node
```bash
# apt -y install nfs-common
ssh control1 "apt -y install nfs-common"
ssh control1 "sudo apt -y install nfs-common"
ssh control2 "sudo apt -y install nfs-common"
ssh control3 "sudo apt -y install nfs-common"
ssh worker1 "sudo apt -y install nfs-common"
ssh worker2 "sudo apt -y install nfs-common"

# Add nfs storage class provider: NFS Subdirectory External Provisioner Helm Repository
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

# Install NFS Provisioner

helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=192.168.0.30 --set nfs.path=/nfs --set storageClass.defaultClass=true -n nfs --create-namespace

```
Create a pod to test nfs-provisioner:
- nfs-test.yaml
```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hostpath-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: "nfs-client"
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-pvc1
# This pod uses a PersistentVolumeClaim to access storage
spec:
  containers:
    - name: mycontainer
      image: busybox
      command: ["sh", "-c", "echo Hello from storage > /data/hello.txt && sleep 3600"]
      volumeMounts:
        - mountPath: "/data"
          name: hostpath-storage
  volumes:
    - name: hostpath-storage
      persistentVolumeClaim:
        claimName: hostpath-pvc
  restartPolicy: Never
```
```bash
kubectl apply -f nfs-test.yaml
```
---
# Vault Secret Operator

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```
Create answer file for vault:
- vault-values.yaml
```yaml
server:
  dev:
    enabled: true
    devRootToken: "root"
  logLevel: debug
ui:
  enabled: true
injector:
  enabled: false
```
Install vault
```bash
helm install vault hashicorp/vault -n vault --create-namespace --values vault-values.yaml
```
Wait for the Vault pod to get ready:
```bash
kubectl wait --for=condition=Ready -n vault pod/vault-0
```
Port-forward and access Vault UI:
```bash
kubectl port-forward --address 0.0.0.0 -n vault svc/vault-ui 8200:8200
```
Open Vault UI and sign in with token "root".

Use Vault UI to enable and configure Kubernetes authentication, KV secrets engine, a role and policy for Kubernetes, and create a static secret.

Enable Kubernetes authentication:

navigate to Access -> Enable new method -> Kubernetes
use path kubernetes
save
use https://kubernetes.default:443 for Kubernetes host
From the main menu create a new ACL policy named aspnetapp:

path "secret/data/aspnetapp" {
   capabilities = ["read", "list"]
}

Now create a Kubernetes role:

go back to Kubernetes authentication
create a new role aspnetapp with:
Bound service account names: aspnetapp
Bound service account namespaces: default
Generated Token's Policies: aspnetapp
Audience: vault
This role enables service account aspnetapp to use policy aspnetapp which allows access to secrets under a specific path in the KV secrets engine.

Finally, add secrets under secret/aspnetapp, e.g.:

{
  "Redis__Password": "password123"
}

## Vault Secrets Operator

Deploy Vault Secrets Operator

Use Helm to deploy the Vault Secrets Operator:
- vault-operator-values.yaml 
```yaml
defaultVaultConnection:
  enabled: true
  address: "http://vault.vault.svc.cluster.local:8200"
  skipTLSVerify: false
```
- Install secret opeator:
```bash
helm install vault-secrets-operator hashicorp/vault-secrets-operator -n vault-secrets-operator-system --create-namespace --values vault-operator-values.yaml
```
Wait for the operator pod to get ready:
```bash
kubectl get pods -n vault-secrets-operator-system -w
```
Now deploy the aspnetapp together with a Vault static secret:
```bash
kubectl apply -f /aspnetapp.yaml
```
Wait for the aspnetapp pod to get ready:
```bash
kubectl get pods -w
```
Finally, access aspnetapp at link.

To inspect the created Kubernetes secret, run:
```bash
kubectl get secret aspnetapp-vault-secret --template='{{.data.Redis__Password}}' | base64 -d
```
Observe that you can read secret via vault secret operator.
---
- aspnetapp.yaml 
```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aspnetapp
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: aspnetapp-vault-auth
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: aspnetapp
    serviceAccount: aspnetapp
    audiences:
      - vault
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: aspnetapp
spec:
  type: kv-v2
  mount: secret
  path: aspnetapp
  destination:
    name: aspnetapp-vault-secret
    create: true
  refreshAfter: 30s
  vaultAuthRef: aspnetapp-vault-auth
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aspnetapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aspnetapp
  template:
    metadata:
      labels:
        app: aspnetapp
    spec:
      serviceAccountName: aspnetapp
      containers:
      - name: aspnetapp
        image: registry.gitlab.com/solve-x-kubernetes/aspnetapp:main
        ports:
        - containerPort: 8080
        envFrom:
        - secretRef:
            name: aspnetapp-vault-secret
---
apiVersion: v1
kind: Service
metadata:
  name: aspnetapp
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 32080
  selector:
    app: aspnetapp
```
