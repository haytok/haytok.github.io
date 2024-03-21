---
draft: false
title: "How to develop containerd and nerdctl"
date: 2024-03-21T22:33:20+09:00
tags: ["containerd", "nerdctl"]
pinned: true
ogimage: "img/images/202403021.png"
---

## Overview

This entry describes the basic commands and the configurations for developing `containerd` and `nerdctl` on M3 Mac Air.

## Notes

### Basic commands

Start Lima VM

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

- https://lima-vm.io/docs/examples/

Exec in Lima VM

```bash
limactl shell default
```
