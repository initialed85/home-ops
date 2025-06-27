# home-ops

This repo contains all the stuff around my home setup

## Hacks

These section is mostly notes for myself, I've put them at the top so they stick out.

- I needed
  [this patch](https://forums.developer.nvidia.com/t/gpl-only-symbols-follow-pte-and-rcu-read-unlock-prevent-470-256-02-to-build-with-kernel-6-10/300052/6)
  to the latest Nvidia 470 branch drivers to get them to build for kernel 6.10
- Only ROCM 6.2 (latest) would build for kernel 6.10 (sort of)

## Services

It varies over time, but the hosted services are more less:

- Home Assistant (running on the official Odroid or whatever it is appliance)
- MQTT broker
- Various bespoke home automation code for my hacky projects (sprinklers, aircons, heater, LED string lights)
- CCTV cameras presently using [initialed85/cameranator](https://github.com/initialed85/cameranator) but soon
  [initialed85/camry](https://github.com/initialed85/camry)
- SMB server and file browser for the scanner
- Minecraft server
- Quake with WebSocket multiplayer server
- Various other projects / games that I've written

## Nodes

I've got a mixture of old x86 laptops, one desktop, one server and two Raspberry Pis- some of the nodes have GPUs.

- OS and drivers
  - Ubuntu 22.04
  - [zabbly/linux](https://github.com/zabbly/linux) for the kernel
  - [zabbly/zfs](https://github.com/zabbly/zfs) for ZFS support
  - Where applicable
    - Nvidia 470.223.02 and [keylase/nvidia-patch](https://github.com/keylase/nvidia-patch) to defeat encoding session
      limits
    - AMD ROCm
- High-availability
  - Keepalived (so my router only has to know about one virtual IP)
  - HAProxy (so whoever has the virtual IP will round-robin the nodes + provides Traefik w/ all the load-balancer-ish
    proxy headers)
- Storage
  - Dedicated ZFS / NFS file server
- Deployment infrastructure
  - Kubernetes (K3s)

You may wonder- why the high-availability approach yet the single point of failure of the file server?

That boils down to the following:

- Prior versions of my home cluster used Ceph and then Longhorn (for clustered storage) a few times, all were fine until
  they failed catastrophically and (more or less) unrecoverably
- The server I've picked as the file server has shown to be the most reliable node
- Prior versions of my home cluster with a single master node caused too many outages when that node crashed (so with
  HA, my pods will reschedule)

### High availability

My router passes on any of the ports I want to expose to `192.168.137.10` which is a virtual IP, handled by Keepalived.

My Keepalived config looks (approximately) like this:

```
vrrp_instance VI_1 {
    interface eth0
    state MASTER  # only one node is MASTER, the rest are BACKUP
    virtual_router_id 51  # all nodes have the same virtual router ID
    priority 100  # the master has the numerically highest priority, all nodes have unique priorities for determinism
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass some-password
    }
    unicast_peer {
        # 192.168.137.34  # don't have yourself as a peer
        192.168.137.30
        192.168.137.27
        192.168.137.28
        192.168.137.29
    }
    virtual_ipaddress {
        192.168.137.10
    }
}
```

UPDATE: This runs in Kubernetes now (so obvious in hindsight)- just `privileged: true` and `hostNetwork: true` and boom.

### Storage

In light of the prior failures, I now dedicate one of the nodes as a file server, running ZFS for two pools (HDD and
SDD) and exposing that via NFS (which is then consumed as PersistentVolumeClaims in Kubernetes).

ZFS provisioning was something like this (once all drives had been freshly partition w/ Linux partitions):

```shell
sudo zpool create -o ashift=12 -O checksum=on -O compression=lz4 -O atime=off -O relatime=on -O acltype=posixacl -O dedup=off storage-hdd /dev/sdb /dev/sde /dev/sdh
sudo zpool create -o ashift=12 -O checksum=on -O compression=lz4 -O atime=off -O relatime=on -O acltype=posixacl -O dedup=off storage-ssd /dev/sdf1 /dev/sdg1
```

This is a RAID0 setup btw, so maximum storage (and I think speed?) and zero redundancy- my drives are slow and garbage
and small and my data is unimportant so this gives me what I need.

I can't recall the exact commands I ran to install the NFS server (pretty standard stuff though), but `/etc/exports`
looks like this:

```conf
/storage-ssd *(insecure,sync,rw,no_subtree_check,no_root_squash,async)
/storage-hdd *(insecure,sync,rw,no_subtree_check,no_root_squash,async)
```

We haven't yet deployed Argo, but once we do, it'll deploy the pieces necessary to expose NFS for use by
PersistentVolumeClaims.

## Kubernetes provisioning

### Cluster

I ran this to get the K3s cluster running:

```shell
# first node (beefcake-1 - 192.168.137.37)
curl -sfL https://get.k3s.io | K3S_TOKEN=some-token K3S_KUBECONFIG_MODE=644 sh -s - server --cluster-init \
    --flannel-backend=none \
    --disable-network-policy=true \
    --disable=kube-proxy \
    --cluster-cidr=10.42.0.0/16 \
    --service-cidr=10.43.0.0/16 \
    --advertise-address="$(hostname -i)" \
    --node-ip="$(hostname -i)"

# on the high-spec nodes
curl -sfL https://get.k3s.io | K3S_TOKEN=some-token K3S_KUBECONFIG_MODE=644 sh -s - server --server https://192.168.137.37:6443 \
    --flannel-backend=none \
    --disable-network-policy=true \
    --disable=kube-proxy \
    --cluster-cidr=10.42.0.0/16 \
    --service-cidr=10.43.0.0/16 \
    --advertise-address="$(hostname -i)" \
    --node-ip="$(hostname -i)"

# on the low-spec nodes
curl -sfL https://get.k3s.io | K3S_TOKEN=some-token K3S_KUBECONFIG_MODE=644 sh -s - agent --server https://192.168.137.37:6443 \
    --node-ip="$(hostname -i)"
```

| FYI, `/etc/rancher/k3s/k3s/yaml` on the first node is basically `~/.kube/config`, it just needs to have the IP changed
after copying before you can use it on your own workstation.

Then we ship Cilium:

```shell
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown -fR edward:edward ~/.kube/config

cilium install \
    --version 1.17.4 \
    --namespace kube-system \
    --set routingMode=tunnel\ \
    --set tunnelProtocol=geneve \
    --set kubeProxyReplacement=true \
    --set loadBalancer.mode=dsr \
    --set loadBalancer.dsrDispatch=geneve \
    --set "k8sServiceHost=$(hostname -i)" \
    --set k8sServicePort=6443 \
    --set=ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16" \
    --set ipv6.enabled=false

cilium status --wait

cilium connectivity test
```

I made sure to have the following at `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml` on each node:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    dashboard: true
    podAnnotations:
        prometheus.io/port: "8082"
        prometheus.io/scrape: "true"
    providers:
        kubernetesIngress:
            publishedService:
                enabled: "true"
            allowEmptyServices: "true"
            allowExternalNameServices:
                enabled: "true"
    priorityClassName: "system-cluster-critical"
    tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
    service:
        ipFamilyPolicy: "PreferDualStack"
        spec:
            externalTrafficPolicy: Local
    ports:
        web:
            exposedPort: 79
            forwardedHeaders:
                insecure: "true"
                trustedIPs:
                    - 0.0.0.0/0
            proxyProtocol:
                insecure: "true"
                trustedIPs:
                    - 0.0.0.0/0
        websecure:
            exposedPort: 442
            forwardedHeaders:
                insecure: "true"
                trustedIPs:
                    - 0.0.0.0/0
            proxyProtocol:
                insecure: "true"
                trustedIPs:
                    - 0.0.0.0/0
```

Then I ensured I had a `/etc/rancher/k3s/registries.yaml` on each node that read as follows:

```yaml
mirrors:
  "kube-registry:5000":
    endpoint:
      - "http://kube-registry:5000"
configs:
  "kube-registry:5000":
    tls:
      insecure_skip_verify: true
```

This is coupled with an `/etc/hosts` entry on each node that points `kube-registry` to the IP of the node itself; e.g.:

```
192.168.137.34  kube-registry
```

<!-- Next we ship MetalLB:

```shell
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
``` -->

Now we need to deploy the NFS provisioner:

```shell
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm upgrade --atomic --install --namespace kube-system nfs-subdir-external-provisioner-ssd nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=192.168.137.253 --set nfs.path=/storage-ssd --set storageClass.name=nfs-ssd
helm upgrade --atomic --install --namespace kube-system nfs-subdir-external-provisioner-hdd nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=192.168.137.253 --set nfs.path=/storage-hdd --set storageClass.name=nfs-hdd
```

And [bitnami-labs/sealed-secrets](https://github.com/bitnami-labs/sealed-secrets) so we can safely store secrets in this
repo:

```shell
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm upgrade --atomic --install --namespace kube-system sealed-secrets sealed-secrets/sealed-secrets --version 2.17.3
```

Usage is something like this:

```shell
kubectl -n mynamespace create secret generic mysecret --dry-run=client --from-literal='key=value' -o yaml | kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml > mysealedsecret.yaml
```

### SSL certificate vending

[cert-manager](https://cert-manager.io/) is a fantastic way to do SSL for free with
[Let's Encrypt](https://letsencrypt.org/); to ship that:

```shell
# came from curl -L https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
kubectl apply -f _cluster/1-cert-manager.yaml
kubectl apply -f _cluster/2-clusterissuer.yaml
```

### Continuous Deployment

Argo isn't perfect but it seems to be the best out there; to ship that:

```shell
helm repo add argo https://argoproj.github.io/argo-helm

# came from helm show values argo/argo-cd > 3-argocd-values.yaml (which needed some edits)
helm upgrade --atomic --install --namespace argo-cd --create-namespace argo-cd argo/argo-cd --version 8.1.2 --values _cluster/3-argocd-values.yaml

# dump out the secret
kubectl -n argo-cd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

At this point I needed to log in to the Argo UI and add this repo, and also add the `cluster` folder in this repo as the
catalyst for the IaC.

### Continuous Integration

TODO

### Kubevirt

```shell
brew install kubevirt
```
