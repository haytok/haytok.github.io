---
draft: false
title: "How to develop containerd and nerdctl \non Amazon Linux 2023"
date: 2024-04-16T09:47:48Z
tags: ["containerd", "nerdctl"]
pinned: true
ogimage: "img/images/20240416.png"
---

## Overview

While developing [Finch](https://github.com/runfinch/finch), I had a chance to read the source codes for [containerd](https://github.com/containerd/containerd) and [nerdctl](https://github.com/containerd/nerdctl). In order to read their source codes more deeply, I need development and debug environments for [containerd](https://github.com/containerd/containerd) and [nerdctl](https://github.com/containerd/nerdctl).

Therefore, this article will walk you through the process of setting up environments for developing [containerd](https://github.com/containerd/containerd) and [nerdctl](https://github.com/containerd/nerdctl) on Amazon Linux 2023 (EC2 Instance).

## Environments

```bash
[ec2-user@ip-172-31-14-14 ~]$ uname -r
6.1.82-99.168.amzn2023.x86_64
```

## Setup

Setup `.bashrc`

```bash
cat <<EOF >> ~/.bashrc
>
> alias s="source ~/.bashrc"
> alias jake='make -j $(nproc)'
>
> EOF
```

```bash
source ~/.bashrc
```

Update package

```bash
sudo dnf update
```

Install tools to build `containerd` and `nerdctl`

```bash
sudo dnf install -y git make gcc libseccomp-devel iptables
```

Clone `containerd` repository

```bash
git clone https://github.com/containerd/containerd.git
```

Clone `nerdctl` repository

```bash
git clone https://github.com/containerd/nerdctl.git
```

Install `golang 1.22` from source code

```bash
mkdir /tmp/build
goBinary=$(curl -s https://go.dev/dl/ | grep linux | head -n 1 | cut -d'"' -f4 | cut -d"/" -f3)
wget --quiet https://dl.google.com/go/$goBinary -O /tmp/build/$goBinary
sudo tar -C /usr/local -xzf /tmp/build/$goBinary
echo >>~/.bashrc
echo "export GOPATH=\$HOME/go" >>~/.bashrc
echo "export GOROOT=/usr/local/go" >>~/.bashrc
echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >>~/.bashrc
echo >>~/.bashrc
s
```

Check golang version

```bash
[ec2-user@ip-172-31-14-14 ~]$ go version
go version go1.22.2 linux/amd64
```

Build containerd

```bash
[ec2-user@ip-172-31-14-14 ~]$ cd containerd/
[ec2-user@ip-172-31-14-14 containerd]$ jake
+ bin/ctr
go build  -gcflags=-trimpath=/home/ec2-user/go/src -buildmode=pie  -o bin/ctr -ldflags '-X github.com/containerd/containerd/v2/version.Version=v2.0.0-rc.0-71-g831795901 -X github.com/containerd/containerd/v2/version.Revision=8317959018015f6a1756ec8cd08be1093fd630a2 -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/ctr
+ bin/containerd
go build  -gcflags=-trimpath=/home/ec2-user/go/src -buildmode=pie  -o bin/containerd -ldflags '-X github.com/containerd/containerd/v2/version.Version=v2.0.0-rc.0-71-g831795901 -X github.com/containerd/containerd/v2/version.Revision=8317959018015f6a1756ec8cd08be1093fd630a2 -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/containerd
+ bin/containerd-stress
go build  -gcflags=-trimpath=/home/ec2-user/go/src -buildmode=pie  -o bin/containerd-stress -ldflags '-X github.com/containerd/containerd/v2/version.Version=v2.0.0-rc.0-71-g831795901 -X github.com/containerd/containerd/v2/version.Revision=8317959018015f6a1756ec8cd08be1093fd630a2 -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/containerd-stress
+ bin/containerd-shim-runc-v2
+ binaries
```

Check `containerd` version

```bash
[ec2-user@ip-172-31-14-14 containerd]$ ./bin/containerd --version
containerd github.com/containerd/containerd v2.0.0-rc.0-71-g831795901 8317959018015f6a1756ec8cd08be1093fd630a2
```

Build `nerdctl`

```bash
[ec2-user@ip-172-31-14-14 ~]$ cd nerdctl/
[ec2-user@ip-172-31-14-14 nerdctl]$ jake
GO111MODULE=on CGO_ENABLED=0 GOOS=linux go build -ldflags "-s -w -X github.com/containerd/nerdctl/v2/pkg/version.Version=v2.0.0-beta.4-18-gf25ce7ec -X github.com/containerd/nerdctl/v2/pkg/version.Revision=f25ce7eca83a94719b3e6d94232b15e5767da8d0"   -o /home/ec2-user/nerdctl/_output/nerdctl github.com/containerd/nerdctl/v2/cmd/nerdctl
...
```

Check `nerdctl` version

```bash
[ec2-user@ip-172-31-14-14 nerdctl]$ sudo _output/nerdctl version
WARN[0000] unable to determine buildctl version: exec: "buildctl": executable file not found in $PATH
Client:
 Version:	v2.0.0-beta.4-18-gf25ce7ec
 OS/Arch:	linux/amd64
 Git commit:	f25ce7eca83a94719b3e6d94232b15e5767da8d0
 buildctl:
  Version:
FATA[0000] cannot access containerd socket "/run/containerd/containerd.sock": no such file or directory
```

Install `CNI plugin` using below script in containerd repository

- https://github.com/containerd/containerd/blob/main/script/setup/install-cni

```bash
[ec2-user@ip-172-31-14-14 containerd]$ cd script/setup/
[ec2-user@ip-172-31-14-14 setup]$ ./install-cni
Cloning into '/tmp/tmp.TgLuhu7gNt/plugins'...
...
```

Check installed `CNI plugin`

```bash
[ec2-user@ip-172-31-14-14 setup]$ ls /opt/
aws/        cni/        containerd/
```

Install runc using below script in containerd repository

- https://github.com/containerd/containerd/blob/main/script/setup/install-runc

```bash
[ec2-user@ip-172-31-14-14 setup]$ ./install-runc
Cloning into '/tmp/tmp.oQ9AtggKgg/runc'...
...
```

Run `containerd`

```bash
[ec2-user@ip-172-31-14-14 containerd]$ sudo ./bin/containerd --log-level debug
INFO[2024-04-16T09:01:24.322237430Z] starting containerd                           revision=8317959018015f6a1756ec8cd08be1093fd630a2 version=v2.0.0-rc.0-71-g831795901
...
```

Create a `container` using `nerdctl`

```bash
[ec2-user@ip-172-31-14-14 nerdctl]$ sudo _output/nerdctl run --rm --name test -it alpine sh
/ # echo hello
hello
/ #
```
