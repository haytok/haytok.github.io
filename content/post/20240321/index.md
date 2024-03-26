---
draft: false
title: "How to develop containerd and nerdctl"
date: 2024-03-21T22:33:20+09:00
tags: ["containerd", "nerdctl"]
pinned: true
ogimage: "img/images/202403021.png"
---

## Overview

I recently purchased an [M3 MacBook Air](https://www.apple.com/jp/shop/buy-mac/macbook-air/15%E3%82%A4%E3%83%B3%E3%83%81-m3). Meanwhile, while developing [Finch](https://github.com/runfinch/finch), I had a chance to read the source code for [containerd](https://github.com/containerd/containerd). However, in order to read the [containerd](https://github.com/containerd/containerd) source code, I needed a [containerd](https://github.com/containerd/containerd) development environment.

Therefore, this article will walk you through the process of setting up an environment for developing [containerd](https://github.com/containerd/containerd) and [nerdctl](https://github.com/containerd/nerdctl) on the [M3 MacBook Air](https://www.apple.com/jp/shop/buy-mac/macbook-air/15%E3%82%A4%E3%83%B3%E3%83%81-m3).

## Environments

- [Lima](https://github.com/lima-vm/lima)

## Set up

Install Lima

```bash
brew install lima
```

Start `Lima` VM

```bash
limactl start \
  --name=default \
  --cpus=4 \
  --memory=8 \
  --vm-type=vz \
  --rosetta \
  --mount-type=virtiofs \
  --mount-writable \
  --network=vzNAT \
  template://fedora
```

ref: https://lima-vm.io/docs/examples/

Check `Lima`

```bash
limactl list
```

```bash
haytok ~/workspace
> limactl list
NAME       STATUS     SSH                VMTYPE    ARCH       CPUS    MEMORY    DISK      DIR
default    Running    127.0.0.1:60022    vz        aarch64    4       8GiB      100GiB    ~/.lima/default
```

Execute shell in `Lima`

```bash
limactl shell default
```

ref: https://lima-vm.io/docs/reference/limactl_shell/

Below are the steps to build nerdctl and containerd in instance.

```bash
sudo dnf update -y
sudo dnf install -y make git golang which tree
```

Build [nerdctl](https://github.com/containerd/nerdctl)

```bash
make -j $(nproc)
```

Check the binary of [nerdctl](https://github.com/containerd/nerdctl)

```bash
[haytok@lima-default nerdctl]$ ls _output/
nerdctl
```

Build containerd and install

```bash
make -j $(nproc) && sudo make install
```

## Debug

Here are the steps to rewrite the [containerd](https://github.com/containerd/containerd) source code and verify that the changes have been applied.

```bash
[haytok@lima-default containerd]$ git diff
diff --git a/cmd/containerd/command/main.go b/cmd/containerd/command/main.go
index cc6260e67..0dc764ee4 100644
--- a/cmd/containerd/command/main.go
+++ b/cmd/containerd/command/main.go
@@ -189,6 +189,7 @@ can be used and modified as necessary as a custom configuration.`
                log.G(ctx).WithFields(log.Fields{
                        "version":  version.Version,
                        "revision": version.Revision,
+                       "developer": "haytok",
                }).Info("starting containerd")

                type srvResp struct {
```

Build and install

```bash
[haytok@lima-default containerd]$ pwd
/Users/haytok/workspace/containerd
[haytok@lima-default containerd]$ make -j $(nproc) && sudo make install
+ bin/ctr
go build  -gcflags=-trimpath=/home/haytok.linux/go/src -buildmode=pie  -o bin/ctr -ldflags '-X github.com/containerd/containerd/v2/version.Version=124456ef8.m -X github.com/containerd/containerd/v2/version.Revision=124456ef83f5984e597c4ab2b48b9074199c1aa0.m -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/ctr
+ bin/containerd
go build  -gcflags=-trimpath=/home/haytok.linux/go/src -buildmode=pie  -o bin/containerd -ldflags '-X github.com/containerd/containerd/v2/version.Version=124456ef8.m -X github.com/containerd/containerd/v2/version.Revision=124456ef83f5984e597c4ab2b48b9074199c1aa0.m -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/containerd
+ bin/containerd-stress
go build  -gcflags=-trimpath=/home/haytok.linux/go/src -buildmode=pie  -o bin/containerd-stress -ldflags '-X github.com/containerd/containerd/v2/version.Version=124456ef8.m -X github.com/containerd/containerd/v2/version.Revision=124456ef83f5984e597c4ab2b48b9074199c1aa0.m -X github.com/containerd/containerd/v2/version.Package=github.com/containerd/containerd -s -w ' -tags "urfave_cli_no_docs"  ./cmd/containerd-stress
+ bin/containerd-shim-runc-v2
+ binaries
+ install bin/ctr bin/containerd bin/containerd-stress bin/containerd-shim-runc-v2
```

Restart `containerd.service` to use the newly generated binary.

```bash
sudo systemctl restart containerd.service
```

Verify that [containerd](https://github.com/containerd/containerd) has been updated.

```bash
sudo journalctl /usr/local/bin/containerd
```

Details are described below.

```bash
[haytok@lima-default containerd]$ sudo journalctl /usr/local/bin/containerd
...
Mar 22 01:35:36 lima-default containerd[31658]: time="2024-03-22T01:35:36.199090673+09:00" level=info msg="starting containerd" developer=haytok revision=124456ef83f5984e597c4ab2b48b9074199c1aa0.m version=124456ef8.m
...
```

As you can see, the source code changes in [containerd](https://github.com/containerd/containerd) have been reflected.

## Notes

### Notes 1

When I try to build [nerdctl](https://github.com/containerd/nerdctl) on [M3 MacBook Air](https://www.apple.com/jp/shop/buy-mac/macbook-air/15%E3%82%A4%E3%83%B3%E3%83%81-m3), I get the following error.

```bash
haytok ~/workspace/nerdctl [main]
> jake
GO111MODULE=on CGO_ENABLED=0 GOOS=darwin go build -ldflags "-s -w -X github.com/containerd/nerdctl/v2/pkg/version.Version=78b66fdc -X github.com/containerd/nerdctl/v2/pkg/version.Revision=78b66fdcde0eeafb95fdf9915dc4ccbaef51021a"   -o /Users/haytok/workspace/nerdctl/_output/nerdctl github.com/containerd/nerdctl/v2/cmd/nerdctl
package github.com/containerd/nerdctl/v2/cmd/nerdctl
	imports github.com/containerd/nerdctl/v2/pkg/defaults: build constraints exclude all Go files in /Users/haytok/workspace/nerdctl/pkg/defaults
package github.com/containerd/nerdctl/v2/cmd/nerdctl
	imports github.com/containerd/nerdctl/v2/pkg/api/types
	imports github.com/containerd/nerdctl/v2/pkg/netutil
	imports github.com/containerd/nerdctl/v2/pkg/lockutil: build constraints exclude all Go files in /Users/haytok/workspace/nerdctl/pkg/lockutil
package github.com/containerd/nerdctl/v2/cmd/nerdctl
	imports github.com/containerd/nerdctl/v2/pkg/clientutil
	imports github.com/containerd/nerdctl/v2/pkg/systemutil: build constraints exclude all Go files in /Users/haytok/workspace/nerdctl/pkg/systemutil
make: *** [nerdctl] Error 1
```

As far as the following issue is concerned, it seems that [nerdctl](https://github.com/containerd/nerdctl) cannot be built on MacOS, so [nerdctl](https://github.com/containerd/nerdctl) should be built on [Lima](https://github.com/lima-vm/lima).

> nerdctl doesn't support macOS directly.
> To run nerdctl on macOS, please use Lima (Linux virtual machine with nerdctl preinstalled) https://github.com/lima-vm/lima

- https://github.com/containerd/nerdctl/issues/597

### Notes 2

Stop an instance

```bash
limactl stop default
```

```bash
haytok ~/workspace/nerdctl [main]
> limactl stop default
INFO[0000] Sending SIGINT to hostagent process 31231
INFO[0000] Waiting for the host agent and the driver processes to shut down
INFO[0000] [hostagent] Received SIGINT, shutting down the host agent
INFO[0000] [hostagent] Shutting down the host agent
INFO[0000] [hostagent] Shutting down VZ
INFO[0000] [hostagent] [VZ] - vm state change: stopped
ERRO[0000] [hostagent] accept tcp 127.0.0.1:60022: use of closed network connection
```

Delete an instance

```bash
limactl delete default
```

Details are described below.

```bash
haytok ~/workspace/bigmo/api/src [feat/#81]
> limactl delete default
INFO[0000] The vz driver process seems already stopped
INFO[0000] The host agent process seems already stopped
INFO[0000] Removing /Users/haytok/.lima/default under "*.pid *.sock *.tmp"
INFO[0000] Removing "/Users/haytok/.lima/default/default_ep.sock"
INFO[0000] Removing "/Users/haytok/.lima/default/default_fd.sock"
INFO[0000] Removing "/Users/haytok/.lima/default/ha.sock"
INFO[0000] Deleted "default" ("/Users/haytok/.lima/default")
```
