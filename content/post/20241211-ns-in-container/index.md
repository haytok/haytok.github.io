---
draft: false
title: "Ns in Container"
date: 2024-12-10T16:06:49Z
tags: ["nerdctl", "containerd", "rootless", "ns"]
pinned: false
ogimage: "img/images/20241211-ns-in-container.png"
---

## Overview

...

## Investigation

Nginx のコンテナを起動

```bash
[ec2-user@ip-172-31-40-91 ~]$ n ps
CONTAINER ID    IMAGE                             COMMAND                   CREATED              STATUS    PORTS                     NAMES
d8e2d622b3d7    docker.io/library/nginx:latest    "/docker-entrypoint.…"    About an hour ago    Up        127.0.0.1:8080->80/tcp    nginx-d8e2d
```

Nginx のコンテナのプロセス ID を確認

```bash
[ec2-user@ip-172-31-40-91 ~]$ n inspect d8e2d622b3d7 --format '{{.State.Pid}}'
126799

[ec2-user@ip-172-31-40-91 ~]$ ps 126799
    PID TTY      STAT   TIME COMMAND
 126799 ?        Ss     0:00 nginx: master process nginx -g daemon off;
```

ns は `/proc/$PID/ns` にあるので確認

```bash
[ec2-user@ip-172-31-40-91 ~]$ ls -la /proc/126799/ns/
total 0
dr-x--x--x. 2 ec2-user ec2-user 0 Dec 10 14:33 .
dr-xr-xr-x. 9 ec2-user ec2-user 0 Dec 10 14:33 ..
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 cgroup -> 'cgroup:[4026532279]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 ipc -> 'ipc:[4026532277]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:33 mnt -> 'mnt:[4026532275]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:33 net -> 'net:[4026532280]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 pid -> 'pid:[4026532278]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 pid_for_children -> 'pid:[4026532278]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 time -> 'time:[4026531834]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 time_for_children -> 'time:[4026531834]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 user -> 'user:[4026532152]'
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:37 uts -> 'uts:[4026532276]'
```

初期状態ではそもそも `/var/run/netns/` がないので、ディレクトリを手動で作成

```bash
[ec2-user@ip-172-31-40-91 ~]$ sudo mkdir /var/run/netns/
```

`ip netns コマンド` から ns を扱うために、`/var/run/netns/` に `/proc/$PID/ns/net` のシンボリックリンクを貼る。


```bash
[ec2-user@ip-172-31-40-91 ~]$ sudo ln -s /proc/126799/ns/net /var/run/netns/nerdctl-ns-126799

[ec2-user@ip-172-31-40-91 ~]$ sudo ip netns list
nerdctl-ns-126799
```

`nerdctl-ns-126799` に入る前に、ホストのネットワーク情報と nginx コンテナの local IP を確認

```bash
[ec2-user@ip-172-31-40-91 ~]$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
    link/ether 06:e6:fc:f5:ba:77 brd ff:ff:ff:ff:ff:ff
    altname enp0s5
    altname eni-0f67ca2c1917ee11c
    altname device-number-0.0
    inet 172.31.40.91/20 metric 512 brd 172.31.47.255 scope global dynamic ens5
       valid_lft 3526sec preferred_lft 3526sec
    inet6 fe80::4e6:fcff:fef5:ba77/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever

[ec2-user@ip-172-31-40-91 ~]$ n inspect d8e2d622b3d7 | grep IPAddress
            "IPAddress": "10.4.0.9",
                    "IPAddress": "10.4.0.9",
```

[この記事](https://haytok.github.io/log/20241120-netns/) で検証したように、`nerdctl-ns-126799` でコマンドを実行する。

```bash
[ec2-user@ip-172-31-40-91 ~]$ sudo ip netns exec nerdctl-ns-126799 ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host proto kernel_lo
       valid_lft forever preferred_lft forever
2: eth0@if10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 7e:ce:2d:4f:fe:6d brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.4.0.9/24 brd 10.4.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::7cce:2dff:fe4f:fe6d/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
```

-> nginx のコンテナが属する Network ns におけるネットワーク情報を確認すると、コンテナの local IP が確認できた。なので、nginx コンテナの Network ns に入れたことが確認できた。

rootless mode で containerd を起動した時、下記のディレクトリに Network ns が存在するんかと思ったけど、違うっぽい ... ???
ほんなら、このディレクトリはどこで使うんや ...

```bash
[ec2-user@ip-172-31-40-91 ~]$ ls /run/user/1000/containerd-rootless/netns
/run/user/1000/containerd-rootless/netns
```

下記の `Rootlesskit Network Design` における図をコマンドを実行して理解する。

- [nerdctl/docs/rootless.md at main · containerd/nerdctl](https://github.com/containerd/nerdctl/blob/main/docs/rootless.md#rootlesskit-network-design)

とりあえず、containerd-rootless の PID を特定し、その PID に紐づく ns から NetNs を特定できるはずなので、関連する PID を確認する。
slirp4netns を起動する際に、`--userns-path=/proc/122351/ns/user` を指定しているが、`122351` の PID が怪しいので、その NetNS を調査してみる。

```bash
[ec2-user@ip-172-31-40-91 ~]$ ps -aux
...
ec2-user  122327  0.0  0.1 1765696 10284 ?       Ssl  13:42   0:00 rootlesskit --state-dir=/run/user/1000/containerd-rootless --net=slirp4netns --mtu=65520 --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin --copy-up=/etc --copy-up=/run --copy-up=/var/lib --propagation=rslave --detach-netns /usr/local/bin/containerd-rootless.sh
ec2-user  122351  0.0  0.1 1917200 9912 ?        Sl   13:42   0:00 /proc/self/exe --state-dir=/run/user/1000/containerd-rootless --net=slirp4netns --mtu=65520 --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin --copy-up=/etc --copy-up=/run --copy-up=/var/lib --propagation=rslave --detach-netns /usr/local/bin/containerd-rootless.sh
ec2-user  122373  0.0  0.0   5264  3380 ?        S    13:42   0:00 slirp4netns --mtu 65520 -r 3 --disable-host-loopback --enable-seccomp --userns-path=/proc/122351/ns/user --netns-type=path /proc/122351/root/run/user/1000/containerd-rootless/netns tap0
...
```

```bash
[ec2-user@ip-172-31-40-91 ~]$ ls -la /proc/122351/ns/net
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:12 /proc/122351/ns/net -> 'net:[4026532201]'
```

```bash
[ec2-user@ip-172-31-40-91 ~]$ sudo ln -s /proc/122351/ns/net /var/run/netns/containerd-rootless-122351
[ec2-user@ip-172-31-40-91 ~]$ sudo ip netns list
containerd-rootless-122351
nerdctl-ns-126799
```

```bash
[ec2-user@ip-172-31-40-91 ~]$ sudo ip netns exec containerd-rootless-122351 ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host proto kernel_lo
       valid_lft forever preferred_lft forever
2: tap0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc fq_codel state UP group default qlen 1000
    link/ether 22:8d:ba:c8:e8:76 brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.100/24 scope global tap0
       valid_lft forever preferred_lft forever
    inet6 fe80::208d:baff:fec8:e876/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
3: buildkit0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 8a:d2:c2:9b:19:ba brd ff:ff:ff:ff:ff:ff
    inet 10.10.0.1/16 brd 10.10.255.255 scope global buildkit0
       valid_lft forever preferred_lft forever
    inet6 fe80::88d2:c2ff:fe9b:19ba/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
5: nerdctl0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 7a:da:45:35:6c:20 brd ff:ff:ff:ff:ff:ff
    inet 10.4.0.1/24 brd 10.4.0.255 scope global nerdctl0
       valid_lft forever preferred_lft forever
    inet6 fe80::78da:45ff:fe35:6c20/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
10: vetha72457ab@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master nerdctl0 state UP group default
    link/ether 5a:34:31:2e:c4:33 brd ff:ff:ff:ff:ff:ff link-netns nerdctl-ns-126799
    inet6 fe80::5834:31ff:fe2e:c433/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
```

-> `tap0` や `nerdctl0` や `vetha72457ab` から、この NetNs は `Rootlesskit Network Design` における `Detach NetNS (Rootlesskit Child NetNS)` であると考えらえる。

コンテナ内から `eth0` は見えている。

```bash
[ec2-user@ip-172-31-40-91 ~]$ n exec -it nginx-d8e2d bash
root@d8e2d622b3d7:/# apt update
...
root@d8e2d622b3d7:/# apt install -y iproute2
...
root@d8e2d622b3d7:/# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0@if10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 7e:ce:2d:4f:fe:6d brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.4.0.9/24 brd 10.4.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::7cce:2dff:fe4f:fe6d/64 scope link
       valid_lft forever preferred_lft forever
```

次に、`Rootlesskit Parent NetNS` を特定する。
おそらく、`slirp4netns` の PID から NetNS を特定できる気がするので、`122373` の PID における NetNS を確認する。

```bash
[ec2-user@ip-172-31-40-91 ~]$ ls -la /proc/122373/ns/net
lrwxrwxrwx. 1 ec2-user ec2-user 0 Dec 10 14:12 /proc/122373/ns/net -> 'net:[4026531840]'
[ec2-user@ip-172-31-40-91 ~]$ sudo ln -s /proc/122373/ns/net /var/run/netns/slirp4netns-122373
[ec2-user@ip-172-31-40-91 ~]$ sudo ip netns list
slirp4netns-122373
containerd-rootless-122351
nerdctl-ns-126799
```

あれ、ホストと同じ `ip a` の結果が返ってきている。

```bash
[ec2-user@ip-172-31-40-91 ~]$ sudo ip netns exec slirp4netns-122373 ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
    link/ether 06:e6:fc:f5:ba:77 brd ff:ff:ff:ff:ff:ff
    altname enp0s5
    altname eni-0f67ca2c1917ee11c
    altname device-number-0.0
    inet 172.31.40.91/20 metric 512 brd 172.31.47.255 scope global dynamic ens5
       valid_lft 2038sec preferred_lft 2038sec
    inet6 fe80::4e6:fcff:fef5:ba77/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
```

`Rootlesskit Parent NetNS` ってホストの NetNS やったりする？？？

> Rootlesskit Parent NetNS and Child NetNS are already configured by the startup script containerd-rootless.sh
> Rootlesskit Parent NetNS is the host network namespace
> step1: nerdctl calls containerd in the host network namespace.
> step2: containerd calls runc in the host network namespace.
> step3: runc creates container with dedicated namespaces (e.g network ns) in the Parent netns.
> step4: runc nsenter Rootlesskit Child NetNS before triggering nerdctl ocihook.
> step5: nerdctl ocihook module leverages CNI.
> step6: CNI configures container network namespace: create network interfaces eth0 -> veth0 -> nerdctl0.

-> `Rootlesskit Parent NetNS is the host network namespace` なので合ってそう！！！

なお、コンテナ内から確認できる `eth0@if10` は `Detach NetNS (Rootlesskit Child NetNS)` における `vetha72457ab@if2` とペア (`sudo ip link add name ... type veth peer name ...`) で作られたと考えられる。

## Ref

- [Network Namespace を使用してコンテナのネットワークを理解する - haytok's Website](https://haytok.github.io/log/20241120-netns/)
- [nerdctl/docs/rootless.md at main · containerd/nerdctl](https://github.com/containerd/nerdctl/blob/main/docs/rootless.md#rootlesskit-network-design)
- [vethの対向インターフェイス名を知る](https://zenn.dev/takai404/articles/ce0f4738a4c7a0#veth%E5%AF%BE%E5%90%91%E3%82%A4%E3%83%B3%E3%82%BF%E3%83%BC%E3%83%95%E3%82%A7%E3%82%A4%E3%82%B9%E3%81%AE%E8%A6%8B%E3%81%A4%E3%81%91%E6%96%B9)
