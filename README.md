# home-ops

This repo contains all the stuff around my home setup

## Hacks

These section is mostly notes for myself, I've put them at the top so they stick out.

- I needed [this patch](https://forums.developer.nvidia.com/t/gpl-only-symbols-follow-pte-and-rcu-read-unlock-prevent-470-256-02-to-build-with-kernel-6-10/300052/6) to the latest Nvidia 470 branch drivers to get them to build for kernel 6.10
- Only ROCM 6.2 (latest) would build for kernel 6.10 (sort of)

## Services

It varies over time, but the hosted services are more less:

- Home Assistant (running on the official Odroid or whatever it is appliance)
- MQTT broker
- Various bespoke home automation code for my hacky projects (sprinklers, aircons, heater, LED string lights)
- CCTV cameras presently using [initialed85/cameranator](https://github.com/initialed85/cameranator) but soon [initialed85/camry](https://github.com/initialed85/camry)
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
    - Nvidia 470.223.02 and [keylase/nvidia-patch](https://github.com/keylase/nvidia-patch) to defeat encoding session limits
    - AMD ROCm
- High-availability
  - Keepalived (provide a single presence for the nodes to my router)
- Storage
  - Dedicated ZFS / NFS file server
- Deployment infrastructure
  - Kubernetes (K3s)

You may wonder- why the high-availability approach yet the single point of failure of the file server?

That boils down to the following:

- Prior versions of my home cluster used Ceph and then Longhorn (for clustered storage) a few times, all were fine until they failed catastrophically and (more or less) unrecoverably
- The server I've picked as the file server has shown to be the most reliable node
- Prior versions of my home cluster with a single master node cauesd too many outages when that node crashed (so with HA, my pods will reschedule)

### Storage

In light of the prior failures, I now dedicate one of the nodes as a file server, running ZFS for two pools (HDD and SDD) and exposing that via NFS (which is then consumed as
PersistentVolumeClaims in Kubernetes).

ZFS provisioning was something like this (once all drives had been freshly partition w/ Linux partitions):

```shell
sudo zpool create -o ashift=12 storage-hdd /dev/sdb /dev/sde /dev/sdh
sudo zpool create -o ashift=12 storage-ssd /dev/sdf1 /dev/sdg1
```

I can't recall the exact commands I ran to install the NFS server (pretty standard stuff though), but `/etc/exports` looks like this:

```
/storage-ssd *(insecure,sync,rw,no_subtree_check,no_root_squash,async)
/storage-hdd *(insecure,sync,rw,no_subtree_check,no_root_squash,async)
```

We haven't yet deployed Argo, but once we do, it'll deploy the pieces necessary to expose NFS for use by PersistentVolumeClaims.

## Kubernetes provisioning

### Cluster

I ran this to get the K3s cluster running:

```shell
# first node (ocnus)
curl -sfL https://get.k3s.io | K3S_TOKEN=some-token K3S_KUBECONFIG_MODE=644 sh -s - server --cluster-init

# subsequent nodes
curl -sfL https://get.k3s.io | K3S_TOKEN=some-token K3S_KUBECONFIG_MODE=644 sh -s - server --server https://192.168.137.34:6443

# on the low-spec nodes
curl -sfL https://get.k3s.io | K3S_TOKEN=some-token K3S_KUBECONFIG_MODE=644 sh -s - agent --server https://192.168.137.34:6443
```

| FYI, `/etc/rancher/k3s/k3s/yaml` on the first node is basically `~/.kube/config`, it just needs to have the IP changed after copying before you can use it on your own workstation.

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

We haven't yet deployed Argo, but once we do, it'll deploy the private registry.

### SSL certificate vending

[cert-manager](https://cert-manager.io/) is a fantastic way to do SSL for free with [Let's Encrypt](https://letsencrypt.org/); to ship that:

```shell
cd _cluster

# came from curl -L https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
kubectl apply -f 1-cert-manager.yaml

kubectl apply -f 2-clusterissuer.yaml
```

### Continuous Deployment

Argo isn't perfect but it seems to be the best out there; to ship that:

```shell
cd _cluster

helm repo add argo https://argoproj.github.io/argo-helm

# came from helm show values argo/argo-cd > 3-argocd-values.yaml (which needed some edits)
helm upgrade --atomic --install --namespace argo-cd --create-namespace argo-cd argo/argo-cd --version 7.0.0 --values 3-argocd-values.yaml
```
