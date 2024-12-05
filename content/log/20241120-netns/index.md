---
draft: false
title: "Network Namespace を使用してコンテナのネットワークを理解する"
date: 2024-11-20T01:56:58Z
tags: ["Linux", "Container"]
pinned: false
ogimage: "img/images/20241120-netns.png"
---

## 概要

コンテナでネットワークを使用する場合、新たに Network Namespace を作成し、様々な設定をすることで、その Network Namespace から外向きの通信をすることが可能となります。
この Work Log では、`ip コマンド` を使用して Network Namespace や仮想ネットワークインターフェイスを作成し、Network Namespace から `ping 8.8.8.8` を実施するための検証を実施してみます。

なお、この記録は後述の参考情報の内容を参考にしているので、新規性はなく、勉強用の記録となっています。

## 検証環境

EC2 インスタンス (Amazon Linux 2023) を使用

```bash
[ec2-user@ip-172-31-42-104 ~]$ uname -r
6.1.115-126.197.amzn2023.x86_64
```

## 検証の大まかな流れ

1. Network Namespace (`test`) を作成する。
2. ホストと Network Namespace 内の双方で使用する veth を作成する。
3. Network Namespace で veth が認識できるように設定する。
4. それぞれの veth に IP を割り振ってリンクアップする。
5. Network Namespace 内で IP のルーティングの設定をする。
6. Network Namespace から来たパケットをホスト側で転送されるような設定をする。

最終的に出来上がる構成は下記になる。

```
NIC <-> ens5 <-> master (veth) <-> (ホスト) | (test Network Namespace) <-> slave (veth) <-> プロセス (ex. ping 8.8.8.8)
```

## 検証

まず、`ip netns コマンド` で `test` という名前の Network Namespace を作る。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ls /var/run/netns
ls: cannot access '/var/run/netns': No such file or directory
# Network Namespace の作成
[ec2-user@ip-172-31-42-104 ~]$ sudo ip netns add test
[ec2-user@ip-172-31-42-104 ~]$ sudo ls /var/run/netns
test
[ec2-user@ip-172-31-42-104 ~]$ sudo ip netns list
test
```

作成した Network Namespace `test` の中に入り、コマンドを実行してみる。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ip netns exec test /bin/bash
[root@ip-172-31-42-104 ec2-user]# ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

-> device は lo 以外生えていない。

veth のペアを作る。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ip link add name master type veth peer name slave
[ec2-user@ip-172-31-42-104 ~]$ ip a
...
3: slave@master: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 8a:2b:18:fc:30:df brd ff:ff:ff:ff:ff:ff
4: master@slave: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether d2:64:55:3d:88:9a brd ff:ff:ff:ff:ff:ff
```

slave は test Network Namespace の方で使えるように変更する。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ip link set slave netns test
```

host からは slave の veth が消えていることを確認できる。

```bash
[ec2-user@ip-172-31-42-104 ~]$ ip a
...
4: master@if3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether d2:64:55:3d:88:9a brd ff:ff:ff:ff:ff:ff link-netns test
```

test Namespace 側から slave の veth が認識できるようになったことを確認

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ip netns exec test /bin/bash
[root@ip-172-31-42-104 ec2-user]# ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
3: slave@if4: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 8a:2b:18:fc:30:df brd ff:ff:ff:ff:ff:ff link-netnsid 0
```

次は、それぞれの veth に IP を付与する。

まずは、master の veth に 192.168.50.101/24 を割り当てて、リンクアップする。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ip addr add 192.168.50.101/24 dev master
[ec2-user@ip-172-31-42-104 ~]$ sudo ip link set dev master up
```

master の veth を確認すると、IP が割り振られ、リンクアップしているのを確認することができた。

```bash
[ec2-user@ip-172-31-42-104 ~]$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
    link/ether 06:3f:68:8a:f3:c1 brd ff:ff:ff:ff:ff:ff
    altname enp0s5
    altname eni-01a724fa62aa38b17
    altname device-number-0.0
    inet 172.31.42.104/20 metric 512 brd 172.31.47.255 scope global dynamic ens5
       valid_lft 2996sec preferred_lft 2996sec
    inet6 fe80::43f:68ff:fe8a:f3c1/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
4: master@if3: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state LOWERLAYERDOWN group default qlen 1000
    link/ether d2:64:55:3d:88:9a brd ff:ff:ff:ff:ff:ff link-netns test
    inet 192.168.50.101/24 scope global master
       valid_lft forever preferred_lft forever
```

slave の方も同様に 192.168.50.102/24 を割り当てて、リンクアップする。

```bash
[root@ip-172-31-42-104 ec2-user]# sudo ip addr add 192.168.50.102/24 dev slave
[root@ip-172-31-42-104 ec2-user]# ip link set dev slave up
```

slave の veth を確認すると、IP が割り振られ、リンクアップしているのを確認することができた。

```bash
[root@ip-172-31-42-104 ec2-user]# ip a
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
3: slave@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 8a:2b:18:fc:30:df brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.50.102/24 scope global slave
       valid_lft forever preferred_lft forever
    inet6 fe80::882b:18ff:fefc:30df/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
```

ここまで来ると、master と slave で通信し合うことはできる。

slave -> master で ping は実行できた。

```bash
[root@ip-172-31-42-104 ec2-user]# ping 192.168.50.101
PING 192.168.50.101 (192.168.50.101) 56(84) bytes of data.
64 bytes from 192.168.50.101: icmp_seq=1 ttl=127 time=0.044 ms
64 bytes from 192.168.50.101: icmp_seq=2 ttl=127 time=0.102 ms
^C
--- 192.168.50.101 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1054ms
rtt min/avg/max/mdev = 0.044/0.073/0.102/0.029 ms
```

master -> slave でも ping は実行できた。

```bash
[ec2-user@ip-172-31-42-104 ~]$ ping 192.168.50.101
PING 192.168.50.101 (192.168.50.101) 56(84) bytes of data.
64 bytes from 192.168.50.101: icmp_seq=1 ttl=127 time=0.017 ms
^C
--- 192.168.50.101 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.017/0.017/0.017/0.000 ms
[ec2-user@ip-172-31-42-104 ~]$ ping 192.168.50.102
PING 192.168.50.102 (192.168.50.102) 56(84) bytes of data.
64 bytes from 192.168.50.102: icmp_seq=1 ttl=127 time=0.022 ms
64 bytes from 192.168.50.102: icmp_seq=2 ttl=127 time=0.038 ms
^C
--- 192.168.50.102 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1088ms
rtt min/avg/max/mdev = 0.022/0.030/0.038/0.008 ms
```

で、こっからが本題で、test Namespace から外に通信をするようにしたいが、現時点の設定では test Network Namespace からは外向きに通信はできない。

```bash
[root@ip-172-31-42-104 ec2-user]# ping 8.8.8.8
ping: connect: Network is unreachable
```

理由の 1 つに、今のとこ、デフォルトゲートウェイがないことが挙げられる。

```bash
[root@ip-172-31-42-104 ec2-user]# ip route
192.168.50.0/24 dev slave proto kernel scope link src 192.168.50.102
```

なので、デフォルトゲートウェイを追加する。

```bash
[root@ip-172-31-42-104 ec2-user]# ip route add default via 192.168.50.101 dev slave
```

これで、デフォルトゲートウェイは master の方に流れる。

```bash
[root@ip-172-31-42-104 ec2-user]# ip route
default via 192.168.50.101 dev slave
192.168.50.0/24 dev slave proto kernel scope link src 192.168.50.102
```

ただ、ホスト側で iptables の変更も必要。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -j MASQUERADE
```

これで test Namespace から 8.8.8.8 に通信できるかと思ったけど、できない ...

```bash
[root@ip-172-31-42-104 ec2-user]# ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
^C
--- 8.8.8.8 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2113ms
```

これは、ホスト側でパケットの転送する sysctl を追加する必要があるためである。

```bash
[ec2-user@ip-172-31-42-104 ~]$ /sbin/sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 0
[ec2-user@ip-172-31-42-104 ~]$ sudo  /sbin/sysctl -w net.ipv4.ip_forward=1
net.ipv4.ip_forward = 1
[ec2-user@ip-172-31-42-104 ~]$ /sbin/sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 1
```

`net.ipv4.ip_forward` を 1 に設定して、再度 Network Namespace test から `ping 8.8.8.8` を実行すると、外向きに通信することができるのを確認できた。

```bash
[ec2-user@ip-172-31-42-104 ~]$ sudo ip netns exec test /bin/bash
[root@ip-172-31-42-104 ec2-user]# ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=116 time=1.39 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=116 time=1.36 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=116 time=1.35 ms
^C
--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 1.345/1.362/1.387/0.017 ms
```

以上より、作成した Network Namespace test から外向きの通信をする検証が成功した。

## 参考情報

- [コマンドを叩いて遊ぶ 〜コンテナ仮想、その裏側〜 - Retrieva TECH BLOG](https://tech.retrieva.jp/entry/2019/04/16/155828)
- [第6回　Linuxカーネルのコンテナ機能［5］ ─ネットワーク | gihyo.jp](https://gihyo.jp/admin/serial/01/linux_containers/0006)
- [Network Namespaceから外部ネットワークへアクセスする - Carpe Diem](https://christina04.hatenablog.com/entry/access-internet-from-network-namespace)
- [2.5. パケット転送をオンにする | Red Hat Product Documentation](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/6/html/load_balancer_administration/s1-lvs-forwarding-vsa)
