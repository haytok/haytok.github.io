---
draft: false
title: "How to run KubeArmor as systemd mode and develop"
date: 2023-08-15T18:13:07+09:00
tags: ["KubeArmor", "Kubernetes", "Linux"]
pinned: true
ogimage: "img/images/20230815.png"
---

## Overview

Recently, I have been interested in an OSS called [KubeArmor](https://github.com/kubearmor/KubeArmor/) and contributing. [KubeArmor](https://github.com/kubearmor/KubeArmor/) is a cloud-native runtime security enforcement system that restricts the behavior of pods in K8s cluster, containers, and nodes (VMs) at the system level.

`Systemd mode` can be used to enforce security enforcement when restricting the behavior of unorchestrated containers and nodes other than orchestrated cotainers in K8s cluster. Detail are described in docs ([Support Matrix - KubeArmor](https://docs.kubearmor.io/kubearmor/quick-links/support_matrix)) and is provided below.

> Containerized: Workloads that are containerized but not k8s orchestrated are supported. KubeArmor installed in systemd mode can be used to protect such workloads.

> VM/Bare-Metals: Workloads deployed on Virtual Machines or Bare Metal i.e. workloads directly operating as host/system processes. In this case, Kubearmor is deployed in systemd mode.

This entry describes the steps to build an environment for developing [KubeArmor](https://github.com/kubearmor/KubeArmor/) running in `systemd mode` on `Ubuntu 20.04`. 

Note that I refer to [KubeArmor on VM/Bare-Metal](https://github.com/kubearmor/KubeArmor/blob/main/getting-started/kubearmor_vm.md) and [How to set up an environment to develop KubeArmor](https://haytok.github.io/post/20230723/) for the development environment procedure.

## Steps

Check `uname -r`

```bash
ubuntu@ip-172-31-33-167:~$ uname -r
5.15.0-1040-aws
```

Create a new EC2 instance and connect to it via ssh and update packages.

```bash
ubuntu@ip-172-31-33-167:~$ sudo apt update
```

Clone the KubeArmor repository on home directory.

```bash
ubuntu@ip-172-31-33-167:~$ git clone https://github.com/kubearmor/KubeArmor.git
```

Install `Docker` using [install_docker.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/docker/install_docker.sh)

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/contribution/self-managed-k8s/docker$ ./install_docker.sh
```

Install LLVM and golang and so on using [setup.sh](https://github.com/kubearmor/KubeArmor/blob/main/contribution/self-managed-k8s/setup.sh)

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/contribution/self-managed-k8s$ ./setup.sh
```

Load `.bashrc`

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/contribution/self-managed-k8s$ source ~/.bashrc
```

Download the deb file for KubeArmor from [Release v0.10.2 · kubearmor/KubeArmor](https://github.com/kubearmor/KubeArmor/releases/tag/v0.10.2)

```bash
ubuntu@ip-172-31-33-167:~/$ wget https://github.com/kubearmor/KubeArmor/releases/download/v0.10.2/kubearmor_0.10.2_linux-amd64.deb
```

Install KubeArmor

```bash
ubuntu@ip-172-31-33-167:~$ sudo apt install -y kubearmor_0.10.2_linux-amd64.deb
```

Run KubeArmor as systemd mode

```bash
ubuntu@ip-172-31-33-167:~$ sudo systemctl start kubearmor
```

Check KubeArmor status

```bash
ubuntu@ip-172-31-33-167:~$ sudo systemctl status kubearmor
● kubearmor.service - KubeArmor
     Loaded: loaded (/lib/systemd/system/kubearmor.service; disabled; vendor preset: enabled)
     Active: active (running) since Tue 2023-08-15 16:07:21 UTC; 50s ago
   Main PID: 7188 (kubearmor)
      Tasks: 10 (limit: 9151)
     Memory: 126.6M
     CGroup: /system.slice/kubearmor.service
             └─7188 /opt/kubearmor/kubearmor
...
```

## How to develop KubeArmor running `systemd mode`

Add logic to output logs

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ git diff
diff --git a/KubeArmor/core/kubeArmor.go b/KubeArmor/core/kubeArmor.go
index b377e5e7..3864ef6f 100644
--- a/KubeArmor/core/kubeArmor.go
+++ b/KubeArmor/core/kubeArmor.go
@@ -407,6 +407,7 @@ func KubeArmor() {
                kg.Printf("Node Annotations: %v", dm.Node.Annotations)
        }

+       kg.Printf("Hello :)\n")
        kg.Printf("OS Image: %s", dm.Node.OSImage)
        kg.Printf("Kernel Version: %s", dm.Node.KernelVersion)
        if dm.K8sEnabled {
```


Build source code for KubeArmor

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ make
cd /home/ubuntu/KubeArmor/KubeArmor; make -C ../protobuf
make[1]: Entering directory '/home/ubuntu/KubeArmor/protobuf'
make[1]: Nothing to be done for 'build'.
make[1]: Leaving directory '/home/ubuntu/KubeArmor/protobuf'
cd /home/ubuntu/KubeArmor/KubeArmor; go mod tidy
cd /home/ubuntu/KubeArmor/KubeArmor; bpftool btf dump file /sys/kernel/btf/vmlinux format c > BPF/vmlinux.h || true
if grep -q bpf '/sys/kernel/security/lsm'; then \
	cd /home/ubuntu/KubeArmor/KubeArmor; go generate ./... || true; \
fi
cd /home/ubuntu/KubeArmor/KubeArmor; CGO_ENABLED=0 go build -ldflags "-X main.BuildDate=2023-08-15T16:18:47Z -X main.GitCommit=ee416a5a -X main.GitBranch=main -X main.GitState=dirty -X main.GitSummary=v0.11.0-4-gee416a5a-dirty" -o kubearmor main.go
```

Disable KubeArmor and delete the process

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ sudo systemctl disable kubearmor
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ KUBEARMOR_PID=$(pidof -s /opt/kubearmor/kubearmor) && sudo kill -9 $KUBEARMOR_PID
```

Fix the kubearmor binary used by systemd

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ sudo cp /home/ubuntu/KubeArmor/KubeArmor/kubearmor /opt/kubearmor/kubearmor
```

Run KubeArmor as systemd mode

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ sudo systemctl start kubearmor
```

Check KubeArmor logs

```bash
ubuntu@ip-172-31-33-167:~$ sudo journalctl -u kubearmor
...
Aug 15 16:31:24 ip-172-31-33-167 kubearmor[7974]: 2023-08-15 16:31:24.370056        INFO        Hello :)
...
```

Thus, from `the Hello :)` logs, we were able to confirm that the binary built with the modified source code is being used.

## Add policy and check

Apply the following policy

```bash
ubuntu@ip-172-31-33-167:~$ cat hostpolicy.yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorHostPolicy
metadata:
  name: hsp-kubearmor-dev-proc-path-block
spec:
  process:
    matchPaths:
    - path: /usr/bin/sleep # try sleep 1
  action:
    Block
```

Apply the policy

```bash
ubuntu@ip-172-31-33-167:~$ karmor vm policy add hostpolicy.yaml
```

If you try to execute the sleep command, it cannot be executed due to the policy.

```bash
ubuntu@ip-172-31-33-167:~$ sleep 1
-bash: /usr/bin/sleep: Permission denied
```

Check KubeArmor events from `karmor logs`

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ karmor logs --gRPC=localhost:32767
Created a gRPC client (localhost:32767)
Checked the liveness of the gRPC server
Started to watch alerts
...
== Alert / 2023-08-15 16:35:51.946785 ==
HostName: ip-172-31-33-167
Type: MatchedHostPolicy
PolicyName: hsp-kubearmor-dev-proc-path-block
Severity: 1
Source: /usr/bin/bash
Resource: /usr/bin/sleep 1
Operation: Process
Action: Block
Data: syscall=SYS_EXECVE
Enforcer: AppArmor
Result: Permission denied
HostPID: 8115
HostPPID: 8106
PID: 8115
PPID: 8106
ParentProcessName: /usr/bin/bash
ProcessName: /usr/bin/sleep
UID: 1000
```

## Note

If you are using `Ubuntu 20.04` on EC2 instance, you may need to run the following command.

```bash
ubuntu@ip-172-31-33-167:~/KubeArmor/KubeArmor$ sudo apt install -y linux-tools-5.15.0-1040-aw
```

## Reference

- [KubeArmor on VM/Bare-Metal](https://github.com/kubearmor/KubeArmor/blob/main/getting-started/kubearmor_vm.md)
- [How to set up an environment to develop KubeArmor](https://haytok.github.io/post/20230723/)
- [Release v0.10.2 · kubearmor/KubeArmor](https://github.com/kubearmor/KubeArmor/releases/tag/v0.10.2)
- [kubearmor/kubearmor-client](https://github.com/kubearmor/kubearmor-client)
