---
draft: false
title: "How to set up an environment to develop KubeArmor"
date: 2023-07-23T01:06:54+09:00
tags: ["KubeArmor", "Kubernetes", "Linux"]
pinned: true
ogimage: "img/images/20230723.png"
---

## Overview

Recently, I have been interested in an OSS called [KubeArmor](https://github.com/kubearmor/KubeArmor/) and have created several pull requests that have been merged. This entry describes the steps to build an environment for developing [KubeArmor](https://github.com/kubearmor/KubeArmor/) on `Ubuntu 20.04`.

Note that I refer to [the Development Guide](https://github.com/kubearmor/KubeArmor/blob/main/contribution/development_guide.md) for the development environment procedure.

## Steps

Check `uname -r`

```bash
ubuntu@ip-172-31-36-15:~$ uname -r
5.15.0-1036-aws
```

Create a new EC2 instance and connect to it via ssh and update packages.

```bash
ubuntu@ip-172-31-36-15:~$ sudo apt update
```

Clone the KubeArmor repository on home directory.

```bash
ubuntu@ip-172-31-36-15:~$ git clone https://github.com/kubearmor/KubeArmor.git
```

Install `Docker` using [install_docker.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/docker/install_docker.sh)

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s/docker$ ./install_docker.sh
```

If you want to use `containerd` as container runtime, use [install_containerd.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/containerd/install_containerd.sh).

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s/containerd$ ./install_containerd.sh
```

If you want to use `cri-o`, use [install_crio.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/crio/install_crio.sh).

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s/crio$ ./install_crio.sh
```

Install k3s and setup Kubernetes cluster using [install_k3s.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/k3s/install_k3s.sh)

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/k3s$ ./install_k3s.sh
```

Check running Pods

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/k3s$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   local-path-provisioner-6c79684f77-ndq4v   1/1     Running   0          53s
kube-system   coredns-d76bd69b-j9l92                    1/1     Running   0          53s
kube-system   metrics-server-7cd5fcb6b7-6vzc6           1/1     Running   0          53s
```

Install LLVM and golang and so on using [setup.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/setup.sh)

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s$ ./setup.sh
```

Load `.bashrc`

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s$ source ~/.bashrc
```

At this time, kind for KubeArmor is not existed

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s$ kubectl api-resources | grep Kube
ubuntu@ip-172-31-36-15:~/KubeArmor/contribution/self-managed-k8s$
```

Build source code for KubeArmor

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ ls
BPF       build   config  enforcer  go.mod  kvmAgent  main.go       monitor    policy     types
Makefile  common  core    feeder    go.sum  log       main_test.go  packaging  templates
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ make
no required module provides package github.com/ahmetb/govvv; to add it:
...
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ ls
BPF       build   config  enforcer  go.mod  kubearmor  log      main_test.go  packaging  templates
Makefile  common  core    feeder    go.sum  kvmAgent   main.go  monitor       policy     types
```

At this time, kind for KubeArmor is not existed

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ kubectl api-resources | grep Kube
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$
```

Exec `kubectl proxy &`

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ kubectl proxy &
[1] 487268
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ Starting to serve on 127.0.0.1:8001
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$
```

Exec `make run`

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ make run
cd /home/ubuntu/KubeArmor/KubeArmor; make -C ../protobuf
...
```

Check running Pods

```bash
ubuntu@ip-172-31-36-15:~$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   local-path-provisioner-6c79684f77-ndq4v   1/1     Running   0          11m
kube-system   coredns-d76bd69b-j9l92                    1/1     Running   0          11m
kube-system   metrics-server-7cd5fcb6b7-6vzc6           1/1     Running   0          11m
```

Found kind of KubeArmorHostPolicy and KubeArmorPolicy

```bash
ubuntu@ip-172-31-36-15:~$ kubectl api-resources | grep Kube
kubearmorhostpolicies             hsp          security.kubearmor.com/v1              false        KubeArmorHostPolicy
kubearmorpolicies                 ksp          security.kubearmor.com/v1              true         KubeArmorPolicy
```

Check running Pods and Deploy a new Pod

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/tests/syscalls$ kubectl apply -f manifests/ubuntu-deployment.yaml
namespace/syscalls created
deployment.apps/ubuntu-1-deployment created
ubuntu@ip-172-31-36-15:~/KubeArmor/tests/syscalls$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   local-path-provisioner-6c79684f77-ndq4v   1/1     Running   0          24h
kube-system   coredns-d76bd69b-j9l92                    1/1     Running   0          24h
kube-system   metrics-server-7cd5fcb6b7-6vzc6           1/1     Running   0          24h
syscalls      ubuntu-1-deployment-9c9dbdb8-9dgpv        1/1     Running   0          64s
```

Check the annotaton of `kubearmor-policy` for the Pod

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/tests/syscalls$ NAMESPACE="syscalls" && POD_NAME=$(kubectl get pods -n $NAMESPACE -l "container=ubuntu-1" -o jsonpath='{.items[0].metadata.name}') && kubectl get pods -n $NAMESPACE $POD_NAME -oyaml | head -n 20
apiVersion: v1
kind: Pod
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/ubuntu-1-container: localhost/kubearmor-syscalls-ubuntu-1-deployment-ubuntu-1-container
    kubearmor-policy: enabled
  creationTimestamp: "2023-07-05T13:55:50Z"
  generateName: ubuntu-1-deployment-9c9dbdb8-
  labels:
    container: ubuntu-1
    pod-template-hash: 9c9dbdb8
  name: ubuntu-1-deployment-9c9dbdb8-9dgpv
  namespace: syscalls
  ownerReferences:
  - apiVersion: apps/v1
    blockOwnerDeletion: true
    controller: true
    kind: ReplicaSet
    name: ubuntu-1-deployment-9c9dbdb8
    uid: 9b8618f2-25a3-4469-99f5-a2573f9af3b7
```

Install ginkgo using [this README.md](https://github.com/kubearmor/KubeArmor/tree/main/tests) as a reference

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/KubeArmor$ go install -mod=mod github.com/onsi/ginkgo/v2/ginkgo
````

Exec `ginkgo -r `

```bash
ubuntu@ip-172-31-36-15:~/KubeArmor/tests/syscalls$ ginkgo -r
Ginkgo detected a version mismatch between the Ginkgo CLI and the version of Ginkgo imported by your packages:
  Ginkgo CLI Version:
    2.9.7
  Mismatched package versions found:
    2.9.5 used by syscalls
...
```

## Reference

