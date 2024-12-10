---
draft: false
title: "How to run containerd in rootless mode"
date: 2024-12-09T15:48:12Z
tags: ["containerd", "nerdctl", "rootless"]
pinned: false
ogimage: "img/images/20241210-run-containerd-in-rootless-mode.png"
---

## Overview

This article will walk you through the process of setting up environments for running [containerd](https://github.com/containerd/containerd) in rootless mode and [nerdctl](https://github.com/containerd/nerdctl) on Amazon Linux 2023 (an EC2 Instance).

## Environments

```bash
[ec2-user@ip-172-31-40-91 ~]$ uname -r
6.1.115-126.197.amzn2023.x86_64
```

Note that I have created an EC2 instance running by the following command, and build on that.

```bash
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --iam-instance-profile Name=$IAM_ROLE \
    --instance-type $INSTANCE_CLAS \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --block-device-mapping '[{"DeviceName": "/dev/xvda", "Ebs": {"VolumeSize": 64}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]"
```

## Setup

Update package

```bash
sudo dnf update
```

Install tools to build `containerd`, `nerdctl`, and so on ...

```bash
sudo dnf install -y git make gcc libseccomp-devel iptables golang glib2-devel libcap-devel meson ninja-build
sudo dnf groupinstall -y "Development Tools"
```

Check golang version

```bash
[ec2-user@ip-172-31-40-91 ~]$ go version
go version go1.22.7 linux/amd64
```

Clone `nerdctl` repository and Build `nerdctl`

```bash
cd ~
git clone https://github.com/containerd/nerdctl.git
cd nerdctl/
jake && sudo make install
```

Install [rootlesskit](https://github.com/rootless-containers/rootlesskit) to run [containerd-rootless-setuptool.sh](https://github.com/containerd/nerdctl/blob/main/extras/rootless/containerd-rootless-setuptool.sh)

```bash
cd ~
git clone https://github.com/rootless-containers/rootlesskit.git
cd rootlesskit/
jake && sudo make install
```

Check [rootlesskit](https://github.com/rootless-containers/rootlesskit) version

```bash
[ec2-user@ip-172-31-40-91 rootlesskit]$ rootlesskit --version
rootlesskit version 2.3.1+dev
```

While [slirp4netns](https://github.com/rootless-containers/slirp4netns) is required to run [containerd-rootless-setuptool.sh](https://github.com/containerd/nerdctl/blob/main/extras/rootless/), `libslirp-dev` is required to build [slirp4netns](https://github.com/rootless-containers/slirp4netns).

However, `libslirp-dev` cannot be installed by `sudo yum install -y libslirp-dev` on Amazon Linux 2023.

Therefore, Let's build and install [libslirp](https://gitlab.freedesktop.org/slirp/libslirp).

```bash
cd ~
git clone https://gitlab.freedesktop.org/slirp/libslirp.git
cd libslirp/
meson build
sudo ninja -C build install
```

Buiild and Install [slirp4netns](https://github.com/rootless-containers/slirp4netns)

```bash
cd ~
git clone https://github.com/rootless-containers/slirp4netns.git
./autogen.sh
./configure --prefix=/usr LDFLAGS=-static
sudo make install
```

Check the path of `libslirp.so.0`

```bash
[ec2-user@ip-172-31-40-91 libslirp]$ sudo find /usr /lib /lib64 -name "libslirp.so.0"
/usr/local/lib64/libslirp.so.0
```

Add the following to `~/.bashrc`

```bash
export LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
```

Note that without this setting, the following error will occur.

```bash
[ec2-user@ip-172-31-40-91 libslirp]$ slirp4netns
slirp4netns: error while loading shared libraries: libslirp.so.0: cannot open shared object file: No such file or directory
```

Check the version of `slirp4netns` 

```bash
[ec2-user@ip-172-31-40-91 ~]$ slirp4netns --version
slirp4netns version 1.3.1+dev
commit: ee1542e1532e6a7f266b8b6118973ab3b10a8bb5
libslirp: 4.8.0.27-799a7
SLIRP_CONFIG_VERSION_MAX: 6
libseccomp: 2.5.3
```

Clone `containerd` repository and Build

```bash
cd ~
git clone https://github.com/containerd/containerd.git
cd containerd/
jake && sudo make install
```

Setup to run `containerd` in `rootless mode`

```bash
~/nerdctl/extras/rootless/containerd-rootless-setuptool.sh install
```

Note that simply executing this shell will result in the error `containerd-rootless.sh[74579]: slirp4netns: error while loading shared libraries: libslirp.so.0: cannot open shared object file: No such file or directory`.
To avoid this error, the systemd unit file has to be customized as follows.

```bash
[ec2-user@ip-172-31-40-91 rootless]$ git diff containerd-rootless-setuptool.sh
diff --git a/extras/rootless/containerd-rootless-setuptool.sh b/extras/rootless/containerd-rootless-setuptool.sh
index 27627640..d8bc2853 100755
--- a/extras/rootless/containerd-rootless-setuptool.sh
+++ b/extras/rootless/containerd-rootless-setuptool.sh
@@ -230,6 +230,7 @@ cmd_entrypoint_install() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                Environment=CONTAINERD_ROOTLESS_ROOTLESSKIT_FLAGS=${CONTAINERD_ROOTLESS_ROOTLESSKIT_FLAGS:-}
                ExecStart=$BIN/${CONTAINERD_ROOTLESS_SH}
                ExecReload=/bin/kill -s HUP \$MAINPID
@@ -279,6 +280,7 @@ cmd_entrypoint_install_buildkit() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                ExecStart="$REALPATH0" nsenter -- buildkitd ${BUILDKITD_FLAG}
                ExecReload=/bin/kill -s HUP \$MAINPID
                RestartSec=2
@@ -324,6 +326,7 @@ cmd_entrypoint_install_buildkit_containerd() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                ExecStart="$REALPATH0" nsenter -- buildkitd ${BUILDKITD_FLAG}
                ExecReload=/bin/kill -s HUP \$MAINPID
                RestartSec=2
@@ -352,6 +355,7 @@ cmd_entrypoint_install_bypass4netnsd() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                ExecStart="${command_v_bypass4netnsd}"
                ExecReload=/bin/kill -s HUP \$MAINPID
                RestartSec=2
@@ -387,6 +391,7 @@ cmd_entrypoint_install_fuse_overlayfs() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                ExecStart="$REALPATH0" nsenter containerd-fuse-overlayfs-grpc "${XDG_RUNTIME_DIR}/containerd-fuse-overlayfs.sock" "${XDG_DATA_HOME}/containerd-fuse-overlayfs"
                ExecReload=/bin/kill -s HUP \$MAINPID
                RestartSec=2
@@ -431,6 +436,7 @@ cmd_entrypoint_install_stargz() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                Environment=IPFS_PATH=${XDG_DATA_HOME}/ipfs
                ExecStart="$REALPATH0" nsenter -- containerd-stargz-grpc -address "${XDG_RUNTIME_DIR}/containerd-stargz-grpc/containerd-stargz-grpc.sock" -root "${XDG_DATA_HOME}/containerd
-stargz-grpc" -config "${XDG_CONFIG_HOME}/containerd-stargz-grpc/config.toml"
                ExecReload=/bin/kill -s HUP \$MAINPID
@@ -474,6 +480,7 @@ cmd_entrypoint_install_ipfs() {

                [Service]
                Environment=PATH=$BIN:/sbin:/usr/sbin:$PATH
+               Environment=LD_LIBRARY_PATH=/usr/local/lib64/:$LD_LIBRARY_PATH
                Environment=IPFS_PATH=${IPFS_PATH}
                ExecStart="$REALPATH0" nsenter -- ipfs daemon $@
                ExecReload=/bin/kill -s HUP \$MAINPID
```

Run [containerd-rootless-setuptool.sh](https://github.com/containerd/nerdctl/blob/main/extras/rootless/containerd-rootless-setuptool.sh)

```bash
[ec2-user@ip-172-31-40-91 rootless]$ ./containerd-rootless-setuptool.sh install
[INFO] Checking RootlessKit functionality
[INFO] Checking cgroup v2
[INFO] Checking overlayfs
[INFO] Requirements are satisfied
[INFO] Creating "/home/ec2-user/.config/systemd/user/containerd.service"
[INFO] Starting systemd unit "containerd.service"
+ systemctl --user start containerd.service
+ sleep 3
+ systemctl --user --no-pager --full status containerd.service
● containerd.service - containerd (Rootless)
     Loaded: loaded (/home/ec2-user/.config/systemd/user/containerd.service; disabled; preset: disabled)
     Active: active (running) since Mon 2024-12-09 18:03:32 UTC; 3s ago
   Main PID: 74782 (rootlesskit)
      Tasks: 25
     Memory: 19.1M
        CPU: 192ms
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/containerd.service
             ├─74782 rootlesskit --state-dir=/run/user/1000/containerd-rootless --net=slirp4netns --mtu=65520 --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin --copy-up=/etc --copy-up=/run --copy-up=/var/lib --propagation=rslave --detach-netns /usr/local/bin/containerd-rootless.sh
             ├─74812 /proc/self/exe --state-dir=/run/user/1000/containerd-rootless --net=slirp4netns --mtu=65520 --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin --copy-up=/etc --copy-up=/run --copy-up=/var/lib --propagation=rslave --detach-netns /usr/local/bin/containerd-rootless.sh
             ├─74842 slirp4netns --mtu 65520 -r 3 --disable-host-loopback --enable-seccomp --userns-path=/proc/74812/ns/user --netns-type=path /proc/74812/root/run/user/1000/containerd-rootless/netns tap0
             └─74858 containerd
...
+ systemctl --user enable containerd.service
Created symlink /home/ec2-user/.config/systemd/user/default.target.wants/containerd.service → /home/ec2-user/.config/systemd/user/containerd.service.
[INFO] Installed "containerd.service" successfully.
[INFO] To control "containerd.service", run: `systemctl --user (start|stop|restart) containerd.service`
[INFO] To run "containerd.service" on system startup automatically, run: `sudo loginctl enable-linger ec2-user`
[INFO] ------------------------------------------------------------------------------------------
[INFO] Use `nerdctl` to connect to the rootless containerd.
[INFO] You do NOT need to specify $CONTAINERD_ADDRESS explicitly.
```

Check that containerd is successfully started in `rootless mode` by pstree command

```bash
[ec2-user@ip-172-31-40-91 ~]$ pstree
systemd─┬─2*[agetty]
...
        ├─systemd─┬─(sd-pam)
        │         └─rootlesskit─┬─exe─┬─containerd───6*[{containerd}]
        │                       │     └─8*[{exe}]
        │                       ├─slirp4netns
        │                       └─6*[{rootlesskit}]
...
```

`nerdctl` can be run without `sudo`, so the following result shows that `containerd` can be run in `rootless mode`.

```bash
[ec2-user@ip-172-31-40-91 ~]$ ~/nerdctl/_output/nerdctl ps
CONTAINER ID    IMAGE    COMMAND    CREATED    STATUS    PORTS    NAMES
```

Pull an images

```bash
[ec2-user@ip-172-31-40-91 ~]$ ~/nerdctl/_output/nerdctl pull alpine
docker.io/library/alpine:latest:                                                  resolved       |++++++++++++++++++++++++++++++++++++++|
index-sha256:21dc6063fd678b478f57c0e13f47560d0ea4eeba26dfc947b2a4f81f686b9f45:    done           |++++++++++++++++++++++++++++++++++++++|
manifest-sha256:2c43f33bd1502ec7818bce9eea60e062d04eeadc4aa31cad9dabecb1e48b647b: done           |++++++++++++++++++++++++++++++++++++++|
config-sha256:4048db5d36726e313ab8f7ffccf2362a34cba69e4cdd49119713483a68641fce:   done           |++++++++++++++++++++++++++++++++++++++|
layer-sha256:38a8310d387e375e0ec6fabe047a9149e8eb214073db9f461fee6251fd936a75:    done           |++++++++++++++++++++++++++++++++++++++|
elapsed: 3.4 s                                                                    total:  3.5 Mi (1.0 MiB/s)
```

However, a container can't be run ...

```bash
[ec2-user@ip-172-31-40-91 ~]$ nerdctl run --rm -it alpine sh
FATA[0000] failed to verify networking settings: failed to create default network: needs CNI plugin "bridge" to be installed in CNI_PATH ("/opt/cni/bin"), see https://github.com/containernetworking/plugins/releases: exec: "/opt/cni/bin/bridge": stat /opt/cni/bin/bridge: no such file or directory
```

Setup CNI plugin using [install-cni](https://github.com/containerd/containerd/blob/main/script/setup/install-cni) in `containerd` repository

```bash
~/containerd/script/setup/install-cni
```

Error occurs due to lack of `runc`

```bash
[ec2-user@ip-172-31-40-91 ~]$ nerdctl run --rm -it alpine sh
FATA[0000] failed to create shim task: OCI runtime create failed: unable to retrieve OCI runtime error (open /run/containerd/io.containerd.runtime.v2.task/default/d7cbacc91e7a6dd51576d7344ec0ccbba8de88b67c4fccd93ea0275401d1129c/log.json: no such file or directory): exec: "runc": executable file not found in $PATH: <nil>
```

Install `runc` using [install-runc](https://github.com/containerd/containerd/blob/main/script/setup/install-runc)

```bash
~/containerd/script/setup/install-run
```

The container could be started in rootless mode.

```bash
[ec2-user@ip-172-31-40-91 ~]$ nerdctl run --rm -it alpine sh
/ # echo Hello
Hello
```

However, `nerdctl build` fails because `buildkitd` is not working.

```bash
[ec2-user@ip-172-31-40-91 ~]$ cat Dockerfile
FROM mcr.microsoft.com/devcontainers/python:1-3.12-bullseye
[ec2-user@ip-172-31-40-91 ~]$ nerdctl build -t test .
ERRO[0000] `buildctl` needs to be installed and `buildkitd` needs to be running, see https://github.com/moby/buildkit , and `containerd-rootless-setuptool.sh install-buildkit` for OCI worker or `containerd-rootless-setuptool.sh install-buildkit-containerd` for containerd worker  error="failed to ping to host unix:///run/user/1000/buildkit-default/buildkitd.sock: exec: \"buildctl\": executable file not found in $PATH\nfailed to ping to host unix:///run/user/1000/buildkit/buildkitd.sock: exec: \"buildctl\": executable file not found in $PATH"
FATA[0000] no buildkit host is available, tried 2 candidates: failed to ping to host unix:///run/user/1000/buildkit-default/buildkitd.sock: exec: "buildctl": executable file not found in $PATH
failed to ping to host unix:///run/user/1000/buildkit/buildkitd.sock: exec: "buildctl": executable file not found in $PATH
```

Install `buildkitd`

```bash
cd ~
wget https://github.com/moby/buildkit/releases/download/v0.18.1/buildkit-v0.18.1.linux-amd64.tar.gz
tar -zxvf buildkit-v0.18.1.linux-amd64.tar.gz
rm buildkit-v0.18.1.linux-amd64.tar.gz
sudo cp bin/buildkitd /usr/local/bin/
sudo cp bin/buildctl /usr/local/bin/
```

Run `buildkitd` using Run `buildkitd` using [containerd-rootless-setuptool.sh](https://github.com/containerd/nerdctl/blob/main/extras/rootless/containerd-rootless-setuptool.sh) install-buildkit

```bash
[ec2-user@ip-172-31-40-91 ~]$ ./nerdctl/extras/rootless/containerd-rootless-setuptool.sh install-buildkit
[INFO] Creating "/home/ec2-user/.config/systemd/user/buildkit.service"
[INFO] Starting systemd unit "buildkit.service"
+ systemctl --user start buildkit.service
+ sleep 3
+ systemctl --user --no-pager --full status buildkit.service
● buildkit.service - BuildKit (Rootless)
     Loaded: loaded (/home/ec2-user/.config/systemd/user/buildkit.service; disabled; preset: disabled)
     Active: active (running) since Tue 2024-12-10 08:47:30 UTC; 3s ago
   Main PID: 111644 (buildkitd)
      Tasks: 8 (limit: 9346)
     Memory: 40.8M
        CPU: 184ms
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/buildkit.service
             └─111644 buildkitd --oci-worker=true --oci-worker-rootless=true --containerd-worker=false --oci-worker-net=bridge

...

+ systemctl --user enable buildkit.service
Created symlink /home/ec2-user/.config/systemd/user/default.target.wants/buildkit.service → /home/ec2-user/.config/systemd/user/buildkit.service.
[INFO] Installed "buildkit.service" successfully.
[INFO] To control "buildkit.service", run: `systemctl --user (start|stop|restart) buildkit.service`
```

Check that `buildkitd` is successfully started by pstree command

```bash
[ec2-user@ip-172-31-40-91 ~]$ pstree
systemd─┬─2*[agetty]
...
        ├─systemd─┬─(sd-pam)
        │         ├─buildkitd───7*[{buildkitd}]
        │         ├─dbus-broker-lau───dbus-broker
        │         └─rootlesskit─┬─exe─┬─containerd───7*[{containerd}]
        │                       │     └─8*[{exe}]
        │                       ├─slirp4netns
        │                       └─7*[{rootlesskit}]
...
```

As a result, the Dockerfile can be built in `containerd` running in `rootless mode`.

```bash
[ec2-user@ip-172-31-40-91 ~]$ nerdctl build -t test .
[+] Building 20.6s (5/5) FINISHED
 => [internal] load build definition from Dockerfile                                                                                                                                                                                                      0.0s
...                                                                                                                                                                                                                                 14.2s
unpacking docker.io/library/test:latest (sha256:6fa5092ea21f8410cb91d726c9948d2a7a09749fe4889b65f0753fc76351fefe)...
Loaded image: docker.io/library/test:latest

[ec2-user@ip-172-31-40-91 ~]$ nerdctl images
REPOSITORY    TAG       IMAGE ID        CREATED          PLATFORM       SIZE       BLOB SIZE
test          latest    6fa5092ea21f    2 minutes ago    linux/amd64    1.563GB    563.6MB
alpine        latest    21dc6063fd67    15 hours ago     linux/amd64    8.253MB    3.646MB

[ec2-user@ip-172-31-40-91 ~]$ nerdctl run --rm -it test sh
#
```

## Ref

- [nerdctl/docs/rootless.md at main · containerd/nerdctl](https://github.com/containerd/nerdctl/blob/main/docs/rootless.md)
- [How to develop containerd and nerdctl on Amazon Linux 2023 - haytok's Website](https://haytok.github.io/post/20240416/)
- [slirp / libslirp · GitLab](https://gitlab.freedesktop.org/slirp/libslirp)
- [rootless-containers/slirp4netns: User-mode networking for unprivileged network namespaces](https://github.com/rootless-containers/slirp4netns?tab=readme-ov-file)
- [10.6. systemd のユニットファイルの作成および変更 | Red Hat Product Documentation](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/7/html/system_administrators_guide/sect-managing_services_with_systemd-unit_files#sect-Managing_Services_with_systemd-Unit_Files)
