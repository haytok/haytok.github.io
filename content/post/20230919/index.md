---
draft: false
title: "How to develop KubeArmor running in systemd mode on Amazon Linux 2023"
date: 2023-09-19T21:58:19+09:00
tags: ["KubeArmor", "Container", "Linux"]
pinned: false
ogimage: "img/images/20230919.png"
---

<!-- Amazon Linux 2023 on EC2 で systemd mode で動作する KubeArmor を開発するための環境構築の方法 -->

## Overview

This entry describes the steps for developing `KubeArmor` on `Amazon Linux 2023 no EC2` by running it in `systemd mode`. Note that the procedure is based on the following.

- [test(syscalls): Add an annotation to Pod for syscalls test by haytok](https://github.com/kubearmor/KubeArmor/pull/1297#issuecomment-1627728478)
- [KubeArmor/contribution/self-managed-k8s/setup.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/setup.sh)

## Steps

Create a new Amazon EC2 instance for `Amazon Linux 2023`, Connect to it via ssh ,and Check `uname -r`

```bash
[ec2-user@ip-172-31-42-22 ~]$ uname -r
6.1.49-70.116.amzn2023.x86_64
```

Update packages

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf update
Last metadata expiration check: 0:01:43 ago on Tue Sep 19 14:21:09 2023.
Dependencies resolved.
Nothing to do.
Complete!
```

Install the necessary packages

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf install -y git make bpftool llvm clang elfutils-devel kernel-devel-$(uname -r) 
...
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf groupinstall -y "Development Tools"
...
```

Clone KubeArmor repository

```bash
[ec2-user@ip-172-31-42-22 ~]$ git clone https://github.com/kubearmor/KubeArmor.git
Cloning into 'KubeArmor'...
...
```

Install Docker

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf install -y docker
Last metadata expiration check: 0:07:41 ago on Tue Sep 19 14:21:09 2023.
...
```

Setup Docker

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo systemctl start docker
[ec2-user@ip-172-31-42-22 ~]$ sudo systemctl enable docker
Created symlink /etc/systemd/system/multi-user.target.wants/docker.service → /usr/lib/systemd/system/docker.service.
[ec2-user@ip-172-31-42-22 ~]$ sudo usermod -aG docker $USER
[ec2-user@ip-172-31-42-22 ~]$ newgrp docker
```

Check for Docker commands

```bash
[ec2-user@ip-172-31-42-22 ~]$ docker ps
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

Install packages to set up for Kubernetes 

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf install -y container-selinux
Last metadata expiration check: 0:09:03 ago on Tue Sep 19 14:21:09 2023.
...
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.2.stable.2/k3s-selinux-1.2-2.el8.noarch.rpm
Last metadata expiration check: 0:10:11 ago on Tue Sep 19 14:21:09 2023.
...
```

Install `Golang` and check version

```bash
[ec2-user@ip-172-31-42-22 ~]$ mkdir /tmp/build
[ec2-user@ip-172-31-42-22 ~]$ goBinary=$(curl -s https://go.dev/dl/ | grep linux | head -n 1 | cut -d'"' -f4 | cut -d"/" -f3)
[ec2-user@ip-172-31-42-22 ~]$ wget --quiet https://dl.google.com/go/$goBinary -O /tmp/build/$goBinary
[ec2-user@ip-172-31-42-22 ~]$ sudo tar -C /usr/local -xzf /tmp/build/$goBinary
[ec2-user@ip-172-31-42-22 ~]$ echo >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ echo "export GOPATH=\$HOME/go" >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ echo "export GOROOT=/usr/local/go" >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ echo >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ source ~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ go version
go version go1.20.5 linux/amd64
```

Install `protoc`

```bash
[ec2-user@ip-172-31-42-22 ~]$ mkdir -p /tmp/build/protoc
[ec2-user@ip-172-31-42-22 ~]$ cd /tmp/build/protoc
[ec2-user@ip-172-31-42-22 protoc]$ wget --quiet https://github.com/protocolbuffers/protobuf/releases/download/v3.19.4/protoc-3.19.4-linux-x86_64.zip -O /tmp/build/protoc/protoc-3.19.4-linux-x86_64.zip
[ec2-user@ip-172-31-42-22 protoc]$ unzip protoc-3.19.4-linux-x86_64.zip
Archive:  protoc-3.19.4-linux-x86_64.zip
...
[ec2-user@ip-172-31-42-22 protoc]$ sudo mv bin/protoc /usr/local/bin/
[ec2-user@ip-172-31-42-22 protoc]$ sudo chmod 755 /usr/local/bin/protoc
```

Install `protoc-gen-go`

```bash
[ec2-user@ip-172-31-42-22 ~]$ go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.27.1
go: downloading google.golang.org/protobuf v1.27.1
[ec2-user@ip-172-31-42-22 ~]$ go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2.0
go: downloading google.golang.org/grpc/cmd/protoc-gen-go-grpc v1.2.0
go: downloading google.golang.org/grpc v1.2.0
```

Install `Kubebuilder`

```bash
[ec2-user@ip-172-31-42-22 ~]$ wget --quiet https://github.com/kubernetes-sigs/kubebuilder/releases/download/v3.1.0/kubebuilder_linux_amd64 -O /tmp/build/kubebuilder
[ec2-user@ip-172-31-42-22 ~]$ chmod +x /tmp/build/kubebuilder
[ec2-user@ip-172-31-42-22 ~]$ sudo mv /tmp/build/kubebuilder /usr/local/bin
[ec2-user@ip-172-31-42-22 ~]$ echo 'export PATH=$PATH:/usr/local/kubebuilder/bin' >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ echo >>~/.bashrc
[ec2-user@ip-172-31-42-22 ~]$ source ~/.bashrc
```

Install `kustomize`

```bash
[ec2-user@ip-172-31-42-22 ~]$ cd /tmp/build/
[ec2-user@ip-172-31-42-22 build]$ curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
v5.1.1
kustomize installed to /tmp/build/kustomize
[ec2-user@ip-172-31-42-22 build]$ sudo mv kustomize /usr/local/bin
```

Build KubeArmor

```bash
[ec2-user@ip-172-31-42-22 ~]$ cd KubeArmor/KubeArmor
[ec2-user@ip-172-31-42-22 KubeArmor]$ make -j $(nproc)
which: no govvv in (/home/ec2-user/.local/bin:/home/ec2-user/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/usr/local/go/bin:/home/ec2-user/go/bin)
no required module provides package github.com/ahmetb/govvv; to add it:
...
cd /home/ec2-user/KubeArmor/KubeArmor; CGO_ENABLED=0 go build -ldflags "-X main.BuildDate=2023-09-19T15:44:09Z -X main.GitCommit=27f97083 -X main.GitBranch=main -X main.GitState=clean -X main.GitSummary=27f97083" -o kubearmor main.go
```

Confirm that the kubearmor binary has been created

```bash
[ec2-user@ip-172-31-42-22 KubeArmor]$ ls
BPF       build   config  enforcer  go.mod  kubearmor  log      main_test.go  packaging  templates  utils
Makefile  common  core    feeder    go.sum  kvmAgent   main.go  monitor       policy     types
```

Install rpm to run KubeArmor in `systemd mode`

```bash
[ec2-user@ip-172-31-42-22 ~]$ wget https://github.com/kubearmor/KubeArmor/releases/download/v0.11.0/kubearmor_0.11.0_linux-amd64.rpm
--2023-09-19 15:51:36--  https://github.com/kubearmor/KubeArmor/releases/download/v0.11.0/kubearmor_0.11.0_linux-amd64.rpm
...
2023-09-19 15:51:38 (25.1 MB/s) - ‘kubearmor_0.11.0_linux-amd64.rpm’ saved [44574216/44574216]
```

Note that rpm was downloaded from the following release notes ([Releases v0.11.0](https://github.com/kubearmor/KubeArmor/releases/tag/v0.11.0)).

Also, there is a possibility that such an error will occur.

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo rpm -ivh kubearmor_0.11.0_linux-amd64.rpm
error: Failed dependencies:
	policycoreutils-devel is needed by kubearmor-0:0.11.0-1.x86_64
	setools-console is needed by kubearmor-0:0.11.0-1.x86_64
```

Search for these packages with `dnf search`

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf search policycoreutils-devel
Last metadata expiration check: 1:32:05 ago on Tue Sep 19 14:21:09 2023.
========================================================== Name Exactly Matched: policycoreutils-devel ==========================================================
policycoreutils-devel.x86_64 : SELinux policy core policy devel utilities
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf search setools-console
Last metadata expiration check: 1:32:15 ago on Tue Sep 19 14:21:09 2023.
============================================================= Name Exactly Matched: setools-console =============================================================
setools-console.x86_64 : Policy analysis command-line tools for SELinux
```

Install these packages with `dnf install`

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo dnf install -y policycoreutils-devel setools-console
Last metadata expiration check: 1:33:42 ago on Tue Sep 19 14:21:09 2023.
...
```

Install rpm

```bash
[ec2-user@ip-172-31-42-22 ~]$ sudo rpm -ivh kubearmor_0.11.0_linux-amd64.rpm
Verifying...                          ################################# [100%]
Preparing...                          ################################# [100%]
...
```

Confirm that the installation was successful and that seems to be the case

```bash
[ec2-user@ip-172-31-42-22 KubeArmor]$ ls /opt/kubearmor/
BPF  kubearmor  kubearmor.yaml  templates
```

The shell (`deploy.sh`) used by running KubeArmor is shown below.

```bash
[ec2-user@ip-172-31-42-22 KubeArmor]$ cat deploy.sh
echo "sudo systemctl disable kubearmor";

sudo systemctl disable kubearmor

sleep 5

KUBEARMOR_PID=$(pidof -s /opt/kubearmor/kubearmor) && sudo kill -9 $KUBEARMOR_PID

sleep 5

sudo cp /home/ec2-user/KubeArmor/KubeArmor/kubearmor /opt/kubearmor/kubearmor

sleep 5

echo "systemctl start kubearmor";

sudo systemctl start kubearmor
[ec2-user@ip-172-31-42-22 KubeArmor]$ chmod +x deploy.sh
```

Run `KubeArmor` in systemd mode

```bash
[ec2-user@ip-172-31-42-22 KubeArmor]$ ./deploy.sh
```

Check the results of `sudo journalctl -u kubearmor`

```bash
...
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.828267        INFO        OS Image: Amazon Linux 2023
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.828292        INFO        Kernel Version: 6.1.49-70.116.amzn2023.x86_64
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.828787        INFO        Initialized KubeArmor Logger
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.831805        INFO        Detected mounted BPF filesystem at /sys/fs/bpf
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.833885        INFO        Initializing eBPF system monitor
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.877612        INFO        Successfully added visibility map with key={PidNS:0 MntNS:0} to the kernel
Sep 19 15:57:46 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:46.877676        INFO        eBPF system monitor object file path: /opt/kubearmor/BPF/system_monitor.bpf.o
Sep 19 15:57:47 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:47.199565        INFO        Initialized the eBPF system monitor
Sep 19 15:57:47 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:47.290336        INFO        Initialized KubeArmor Monitor
Sep 19 15:57:47 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:47.290387        INFO        Started to monitor system events
Sep 19 15:57:47 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:47.295687        INFO        Supported LSMs: lockdown,capability,yama,safesetid,selinux,bpf
Sep 19 15:57:51 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:51.857532        INFO        Initialized BPF-LSM Enforcer
Sep 19 15:57:51 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:51.857621        INFO        Initialized KubeArmor Enforcer
Sep 19 15:57:51 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:51.857636        INFO        Started to protect a host and containers
Sep 19 15:57:51 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:51.857708        INFO        Namespace container_namespace visibiliy configured {File:true Process:true Network:true Capabilities:true}
Sep 19 15:57:51 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:51.857954        INFO        Using unix:///run/containerd/containerd.sock for monitoring containers
Sep 19 15:57:51 ip-172-31-42-22.ap-northeast-1.compute.internal kubearmor[45703]: 2023-09-19 15:57:51.859747        INFO        Initialized Containerd Handler
```

Install karmor-client

```bash
[ec2-user@ip-172-31-42-22 ~]$ curl -sfL http://get.kubearmor.io/ | sudo sh -s -- -b /usr/local/bin
```

Create KubeArmorPolicy

```bash
[ec2-user@ip-172-31-42-22 KubeArmor]$ cat <<EOF >> ksp-block-policy.yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: ksp-block-policy
spec:
  severity: 3
  selector:
    matchLabels:
      kubearmor.io/container.name: foo
  process:
    matchPaths:
    - path: /usr/bin/apt
    - path: /usr/bin/apt-get
    # - path: /usr/bin/diff

      # apt update
      # apt-get update

  action:
    Block

EOF
```

Apply KubeArmorPolicy

```bash
[ec2-user@ip-172-31-42-22 ~]$ karmor vm policy add ksp-block-policy.yaml
Success
```

Starting a container with the name specified in KubeArmorPolicy and execute `apt update`, it cannot be executed.

```bash
[ec2-user@ip-172-31-42-22 ~]$ docker run --rm --name foo -it ubuntu bash
root@98bca4f7688b:/# apt update
bash: /usr/bin/apt: Permission denied
```

## Reference

- [test(syscalls): Add an annotation to Pod for syscalls test by haytok](https://github.com/kubearmor/KubeArmor/pull/1297#issuecomment-1627728478)
- [KubeArmor/contribution/self-managed-k8s/setup.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/setup.sh)
