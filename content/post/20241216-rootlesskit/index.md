---
draft: false
title: "recap for the PR fix: allow to propagate the address specified in -p option #477 in rootlesskit"
date: 2024-12-15T04:35:50Z
tags: ["containerd", "nerdctl", "rootless", "rootlesskit"]
pinned: false
ogimage: "img/images/20241216-rootlesskit.png"
---

## How to Develop and Debug

rootless コンテナを起動するための関連ソフトウェアを開発するための環境構築手順

- https://haytok.github.io/post/20241210-run-containerd-in-rootless-mode/

alias の設定

```bash
$ alias
alias jake='make -j $(nproc)'
alias j='journalctl'
alias n='nerdctl'
```

on メインターミナル

```bash
nerdctl ps -a && nerdctl rm -f nginx && nerdctl ps -a && cd ~/rootlesskit && make && sudo make install && sudo systemctl restart user@1000.service

nerdctl run -d --name nginx -p 127.0.0.2:8080:80 nginx && nerdctl ps

curl 127.0.0.2:8080
```

on 別ターミナル

```bash
j -f
```

## rootless コンテナとネットワークネームスペース

Docker コンテナはデフォルトでは root ユーザで実行されるが、rootless コンテナ では root ではない非特権ユーザでコンテナを作成したり実行することが可能。

`sudo ip netns add test` や `sudo ip link add name master type veth peer name slave` のようなコマンドを実行することで NetNS や veth の peer を作成するが、これらのコマンドを実行するには特権ユーザでないとコマンドを実行することができない。
これは veth のペアの片方をホストネットワークに配置する必要があるからである。
そのため、ネットワーキングの設定が必要な rootless コンテナでは問題ないが、rootless コンテナでは後述の `Internal Flow` に記載したような fd passing と fd により作成した `net.Conn` オブジェクトの双方向コピーといった工夫が必要となる。

なお、NetNS とコンテナに関するための理解をまとめた作業ブログは下記になります。

- [Ns in Container - haytok's Website](https://haytok.github.io/post/20241211-ns-in-container/)
- [Network Namespace を使用してコンテナのネットワークを理解する - haytok's Website](https://haytok.github.io/post/20241120-netns/)

また、rootless コンテナのネットワークについては下記の記事が非常に参考になりました。

- [インターンレポート: RootlessコンテナのTCP/IP高速化](https://medium.com/nttlabs/accelerating-rootless-container-network-29d0e908dda4)

## fd passing

rootless コンテナの内部で使用されている fd passing の基本的な内容は下記のリポジトリで公開しているので、必要に応じて参照してください。

- https://github.com/haytok/fd-passing/tree/main/c

## Analysis

rootlesskit を使用して containerd を起動させる。

{{< details summary="起動しているプロセスの確認" >}}

```bash
$ ps aux | grep nerd
ec2-user  157474  0.0  0.1 1856460 21352 ?       Ssl  10:29   0:00 rootlesskit --state-dir=/run/user/1000/containerd-rootless --net=slirp4netns --mtu=65520 --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin --copy-up=/etc --copy-up=/run --copy-up=/var/lib --propagation=rslave --detach-netns /usr/local/bin/containerd-rootless.sh
ec2-user  157494  0.0  0.1 2083744 20620 ?       Sl   10:29   0:00 /proc/self/exe --state-dir=/run/user/1000/containerd-rootless --net=slirp4netns --mtu=65520 --slirp4netns-sandbox=auto --slirp4netns-seccomp=auto --disable-host-loopback --port-driver=builtin --copy-up=/etc --copy-up=/run --copy-up=/var/lib --propagation=rslave --detach-netns /usr/local/bin/containerd-rootless.sh
ec2-user  157525  0.0  0.0   5116  2740 ?        S    10:29   0:00 slirp4netns --mtu 65520 -r 3 --disable-host-loopback --enable-seccomp --userns-path=/proc/157494/ns/user --netns-type=path /proc/157494/root/run/user/1000/containerd-rootless/netns tap0
ec2-user  157533  0.2  0.2 1880464 41736 ?       Ssl  10:29   0:00 containerd
ec2-user  157581  0.0  0.0 222316  2120 pts/2    S+   10:30   0:00 grep --color=auto nerd

$ pstree
systemd─┬─2*[agetty]
...
        ├─systemd─┬─(sd-pam)
        │         └─rootlesskit─┬─exe─┬─containerd───8*[{containerd}]
        │                       │     └─11*[{exe}]
        │                       ├─slirp4netns
        │                       └─8*[{rootlesskit}]
...
```

{{< /details >}}

<br />

containerd が起動した時点で `.bp.sock` は作成済み
このソケットは fd passing をするための UDS であることを確認した。

{{< details summary="`.bp.sock` の確認" >}}

```bash
$ sudo systemctl restart user@1000.service
$ ls -la  /run/user/1000/containerd-rootless/
total 12
drwxr-xr-x. 2 ec2-user ec2-user 200 Aug 17 10:29 .
drwx------. 6 ec2-user ec2-user 320 Aug 17 10:29 ..
prw-------. 1 ec2-user ec2-user   0 Aug 17 10:29 .bp-ready.pipe
srwxr-xr-x. 1 ec2-user ec2-user   0 Aug 17 10:29 .bp.sock
srwxr-xr-x. 1 ec2-user ec2-user   0 Aug 17 10:29 api.sock
-r--r--r--. 1 ec2-user ec2-user   6 Aug 17 10:29 child_pid
-rw-r--r--. 1 ec2-user ec2-user 237 Aug 17 10:29 hosts
-rw-------. 1 ec2-user ec2-user   0 Aug 17 10:29 lock
-r--------. 1 ec2-user ec2-user   0 Aug 17 10:29 netns
-rw-r--r--. 1 ec2-user ec2-user  20 Aug 17 10:29 resolv.conf
```

{{< /details >}}

<br />

## Internal Flow

### Summary

{{<mermaid>}}
sequenceDiagram
    autonumber
    participant Client
    participant Parent as Parent (host NS)
    participant Child as Child (netns)
    participant App as App (container app)

    Note over Parent,App: fd passing に使用される UDS: .bp.sock
    Note over Parent,App: コンテナが起動 (e.g. nerdctl run -d --name nginx -p 127.0.0.2:8080:80 nginx)
    Child->>Child: net.ListenUnix("unix", ...) => ln
    Client->>Parent: TCP connect to ParentIP:ParentPort (e.g. 127.0.0.2:8080)
    Parent->>Parent: Accept() => conn_external // クライアントからのリクエストの終端

    Parent->>Child: Dial(UDS: socketPath)
    Child->>Child: ln.AcceptUnix() => c
    Child->>Child: go d.routine(c, detachedNetNSPath)

    Parent->>Child: JSON Request{Type:"connect", Proto, IP, Port, ParentIP, HostGatewayIP}
    Child->>Child: (optional) ns.WithNetNSPath(...)
    Child->>App: Dial(IP:Port) => targetConn (fd=N)
    Child-->>Parent: Sendmsg(SCM_RIGHTS: fd=N) over UDS

    Parent->>Parent: ReadMsgUnix() => fd=N'

    Parent->>Parent: os.NewFile(uintptr(fd), "") => f, net.FileConn(f) => conn_child
    Parent<<->>Client: bicopy(conn_external <-> conn_child)  // 双方向コピー
{{</mermaid>}}

### Step 1 : rootlesskit を使用して containerd を起動

- Parent
  - `NewDriver()`

- Child
  - `RunChildDriver() `
    - コンテナが作成され、外部からリクエストが飛んでくると、アプリケーション (e.g. Web サーバー) のプロセスが open した fd を fd passing により Parent 側に転送する。
    - for {...} 内の `AcceptUnix()` 呼び出しでブロックします。新しい UDS 接続（＝Parent からの Dial）が来るまで待機し、返ったら goroutine で d.routine() を起動します。

{{< details summary="デバッグログ" >}}

```bash
[DEBUG Parent] 0: In NewDriver
[DEBUG Child] 0: In RunChildDriver, socketPath:  /run/user/1000/containerd-rootless/.bp.sock
[DEBUG Child] 1: In RunChildDriver, before ListenUnix()
[DEBUG Child] 2: In RunChildDriver, before AcceptUnix()
[DEBUG Child] 2: In RunChildDriver, before AcceptUnix()
[DEBUG Child] 3: In RunChildDriver, goroutine, before d.routine()
```

{{< /details >}}

---

### Step 2 : -p オプションを指定してコンテナを起動

- Parent
  - `AddPort()`
  - `tcp.Run()`
- Child
  - なし

Parent 側で外部から 127.0.0.2:8080 に対してリクエストが飛んできた時 (e.g. ホストで curl 127.0.0.2:8080 を実行) に、ホスト側で待ち受けるプロセスを `net.Listen()` と `ln.Accept()` を使用して起動させている。
なお、これが必要なのは実際に起動しているコンテナのアプリケーションは Child の namespace で起動しているので、Parent 側で別途 tcp socket の作成が必要なためである。

なので、外部からリクエストが飛んできた時に、`copyConnToChild()` 以降の処理が始まる。

{{< details summary="コード抜粋 (メイン処理)" >}}

```golang
func Run(socketPath string, spec port.Spec, stopCh <-chan struct{}, stoppedCh chan error, logWriter io.Writer) error {
	ln, err := net.Listen(spec.Proto, net.JoinHostPort(spec.ParentIP, strconv.Itoa(spec.ParentPort)))
...
	newConns := make(chan net.Conn)
	go func() {
		for {
			c, err := ln.Accept()
...
			newConns <- c
		}
	}()
	go func() {
...
		for {
			select {
			case c, ok := <-newConns:
				if !ok {
					return
				}
				go func() {
					if err := copyConnToChild(c, socketPath, spec, stopCh); err != nil {
						fmt.Fprintf(logWriter, "copyConnToChild: %v\n", err)
						return
					}
				}()
			case <-stopCh:
				return
			}
		}
	}()
	// no wait
	return nil
}
```

{{< /details >}}

<br />

{{< details summary="デバッグログ" >}}

```bash
[DEBUG Parent] 0: In AddPort, d.socketPath:  /run/user/1000/containerd-rootless/.bp.sock
[DEBUG Parent] 0: In Run, Listen() tcp 127.0.0.2:8080
[DEBUG Parent] 1: In Run, Accept()
```

{{< /details >}}

---

### Step 3 : curl 127.0.0.2:8080 を実行

- Parent
  - `ln.Accept()` しているので、外部からリクエストが飛んでくると、Child は 指定 IP/Port に対して新規に Dial して その「接続済みソケット（TCPなら ESTABLISHED）」の FD を SCM_RIGHTS で Parent に送ります。
  - `copyConnToChild()`
    - fd passing により得た fd を元に net.Conn オブジェクトを作成し、それを Parent 側で外部からの接続のために作成された ln.Accept() の net.Conn オブジェクトに双方向にコピーする。
  - `ConnectToChildWithRetry()`
    - この関数が Child 側のソケットの実体に対応する fd を passing する。後述の関数を呼び出す上の階層ではリトライ機構を組み込んでいる。
  - `ConnectToChildWithSocketPath()`
    - UDS に対して Dial している。: `conn, err := dialer.Dial("unix", socketPath)`
  - `ConnectToChild()`
    - この関数内では Child に送信するためのデータを Request 型のオブジェクトにして `c.CloseWrite()` により UDS に書き込みを行なっている。その後、`_, oobN, _, _, err = c.ReadMsgUnix(nil, oob)` の直前で Child 側からの fd passing を待機する。なお、この関数内では `// get fd from the child as an SCM_RIGHTS cmsg` のコメントがあるので、これまでの理解が合っていることを確かめられる。
    - なお、Dial は、クライアント側でサーバーに接続を確立する際に頻繁に使用される。
- Child
  - `RunChildDriver()`
    - Parent 側で Dial されたので `ln.AcceptUnix()` 以降の処理が実行される。
  - `routine()`
  - `handleConnectRequest()`
    - Child 側では -p で指定された IP と port 番号でアプリケーションが動くことが期待される。なので、`-p 127.0.0.2:8080:80` を指定すると、Child の `127.0.0.2` と `8080` でアプリケーションが起動しているので、その組み合わせで Dial し、対する fd を取得する。
  - `unix.Sendmsg()`
- Parent
  - `ConnectToChild()` の `c.ReadMsgUnix(nil, oob)` で fd を含むデータが返ってくるので、Parse して fd を取り出す。

{{< details summary="`pkg/port/buildin/child/child.go` の抜粋" >}}

```golang
func (d *childDriver) handleConnectRequest(c *net.UnixConn, req *msg.Request) error {
	fmt.Println("[DEBUG Child] 0: In handleConnectRequest, req: ", req)
	switch req.Proto {
	case "tcp":
...
	default:
		return fmt.Errorf("unknown proto: %q", req.Proto)
	}
	// dialProto does not need "4", "6" suffix
	dialProto := strings.TrimSuffix(strings.TrimSuffix(req.Proto, "6"), "4")
	var dialer net.Dialer
	ip := req.IP
	if ip == "" {
		ip = "127.0.0.1"
		if req.ParentIP != "" {
			if req.ParentIP != req.HostGatewayIP && req.ParentIP != "0.0.0.0" {
				ip = req.ParentIP
			}
		}
	} else {
		p := net.ParseIP(ip)
		if p == nil {
			return fmt.Errorf("invalid IP: %q", ip)
		}
		ip = p.String()
	}
	targetConn, err := dialer.Dial(dialProto, net.JoinHostPort(ip, strconv.Itoa(req.Port)))
...
	targetConnFiler, ok := targetConn.(filer)
...
	targetConnFile, err := targetConnFiler.File()
...
	oob := unix.UnixRights(int(targetConnFile.Fd()))
	// 第一引数の c はここで使われている。
	f, err := c.File()
...
	for {
		err = unix.Sendmsg(int(f.Fd()), []byte("dummy"), oob, nil, 0)
		if err != unix.EINTR {
			break
		}
	}
	return err
}
```

{{< /details >}}

<br />

{{< details summary="デバッグログ" >}}

```bash
[DEBUG Parent] 1: In Run, Accept()
[DEBUG Parent] 2: In Run, before copyConnToChild()
[DEBUG msg] 0: In ConnectToChildWithRetry (この関数では結局 child 側の fd を取得しているだけ)
[DEBUG msg] 0: In ConnectToChildWithSocketPath bfore Dial unix
[DEBUG msg] 0: In ConnectToChild
[DEBUG Child] 2: In RunChildDriver, before AcceptUnix()
[DEBUG Child] 3: In RunChildDriver, goroutine, before d.routine()
~~~~~~~~~~~~~~~~~~
[DEBUG msg] 0: In ConnectToChild, before ReadMsgUnix
[DEBUG Child] 1: In routine, detachedNetNSPath:  /run/user/1000/containerd-rootless/netns
[DEBUG Child] 0: In handleConnectRequest, req:  &{connect tcp  8080 127.0.0.2 172.31.36.62}
DEBUG Child] 0: In handleConnectRequest, before Sendmsg Child namespace 内で起動している web server のようなプロセスに対する socket の fd 13 UDS の fd:  14
[DEBUG Parent] 2: In copyConnToChild, socketPath, fd /run/user/1000/containerd-rootless/.bp.sock 16
```

{{< /details >}}

---
