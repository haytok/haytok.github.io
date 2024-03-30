---
draft: false
title: "How to develop Finch"
date: 2024-02-09T22:33:20+09:00
tags: ["Finch"]
pinned: true
ogimage: "img/images/20240209.png"
---

## Overview

This entry describes the basic commands and the configurations for developing [Finch](https://github.com/runfinch/finch) on Intel Mac.

## Notes

### Basic Settings

When you build Finch on M3 MacBook Air, `vmType` and `rosetta` in `~/.finch/finch.yaml` must be set as follows.

```yaml
haytok ~/workspace/finch [main]
> cat ~/.finch/finch.yaml
cpus: 4
memory: 6GiB
vmType: vz
rosetta: true
```

### Basic commands

Init VM

```bash
haytok finch
> ./_output/bin/finch vm init
INFO[0000] Initializing and starting Finch virtual machine...
INFO[0110] Finch virtual machine started successfully
```

Check VM status

```bash
haytok finch
> ./_output/bin/finch vm status
Nonexistent
```

Stop VM

```bash
haytok finch 
> ./_output/bin/finch vm stop
INFO[0000] Stopping existing Finch virtual machine...
INFO[0005] Finch virtual machine stopped successfully
```

Start VM

```bash
haytok finch 
> ./_output/bin/finch vm start
INFO[0000] Starting existing Finch virtual machine...
INFO[0039] Finch virtual machine started successfully
```

Remove VM

```bash
haytok finch 
> ./_output/bin/finch vm remove
INFO[0000] Removing existing Finch virtual machine...
INFO[0000] Finch virtual machine removed successfully
```
Access VM

```bash
haytok finch [main]
> LIMA_HOME=/Users/haytok/workspace/finch/_output/lima/data/ /Users/haytok/workspace/finch/_output/lima/bin/limactl shell finch
[haytok@lima-finch finch]$
```

### Configuration 1

The following network error may occur when executing the `make` command.

```bash
pkg/lima/wrapper/lima_wrapper.go:10:2: github.com/lima-vm/lima@v0.20.0: Get "https://proxy.golang.org/github.com/lima-vm/lima/@v/v0.20.0.zip": dial tcp: lookup proxy.golang.org: i/o timeout
```

This error can be resolved by setting environment variables.

```bash
haytok finch
> export GOPROXY=direct
```

#### Reference

- [dial tcp: lookup proxy.golang.org i/o timeout · projectdiscovery/httpx · Discussion #658](https://github.com/projectdiscovery/httpx/discussions/658)

### Configuration 2

Setup for local tests using local common-tests repository.

```bash
go mod edit -replace github.com/runfinch/common-tests=../common-tests
```
