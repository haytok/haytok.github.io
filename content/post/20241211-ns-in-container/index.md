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

## Ref

- [Network Namespace を使用してコンテナのネットワークを理解する - haytok's Website](https://haytok.github.io/log/20241120-netns/)
