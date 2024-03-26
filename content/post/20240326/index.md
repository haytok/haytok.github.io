---
draft: false
title: "Dive Deep a bug for nerdctl attach"
date: 2024-03-26T13:34:05Z
tags: ["nerdctl", "containerd"]
pinned: false
ogimage: "img/images/20240326.png"
---

## Description と背景

下記の issue に関して、SDE も色々調査してくれていたが、自分なり調査してまとめる。

- https://github.com/containerd/nerdctl/issues/2877

事の発端は issue に詳しく書いてあります。

## 開発環境 (読み飛ばしても可)

開発環境は基本的に自前の M3 MacBook Air を使用している。
なので、CPU 周りの動作の影響を受けたくないので、ホストのファイルをマウントする形で Lima で VM を構築し、VM からホストのファイルを操作して開発するようにする。

- https://haytok.github.io/post/20240321/

なお、nerdctl ディレクトリにおける `go.mod` は下記のように修正した。

```bash
haytok ~/workspace/nerdctl [main]
> git diff go.mod
diff --git a/go.mod b/go.mod
index 5f985ca7..a832c46a 100644
--- a/go.mod
+++ b/go.mod
@@ -142,3 +142,6 @@ require (
        google.golang.org/protobuf v1.33.0 // indirect
        lukechampine.com/blake3 v1.1.7 // indirect
 )
+
+replace github.com/containerd/containerd => ../containerd
+replace github.com/containerd/fifo => ../fifo
```

こうすると、nerdctl 内で外部パッケージ (containerd や fifo) のソースコードを変更した場合、その変更が nerdctl のビルドしたバイナリに梱包される。

また、containerd と fifo のブランチは nerdctl 内のパッケージのバージョンと合わせる。

```bash
haytok ~/workspace/fifo [(HEAD detached at v1.1.0)]
> git branch
* (HEAD detached at v1.1.0)
  main
haytok ~/workspace/containerd [(HEAD detached at v1.7.14)]
> git branch
* (HEAD detached at v1.7.14)
  main
```

ディレクトリ構成は下記である。

```bash
haytok ~/workspace
> pwd
/Users/haytok/workspace
haytok ~/workspace
> tree -L 1
.
├── bigmo
├── common-tests
├── containerd
├── fifo
├── finch
├── haytok
├── haytok.github.io
├── jobs
├── nerdctl
└── verification

11 directories, 0 files
```


## 調査すること

1. nerdctl attach コマンドを実行した際に発生するエラーを突き止め、そのエラーが発生する条件を調査する。
2. `sudo nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"` を実行した際動作の確認と workaround の調査
3. nerdctl 内で使用されているパッケージ fifo の動作確認

## 調査 1

実際に発生したエラーは下記になります。

```bash
[haytok@lima-finch workspace]$ sudo nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
54f605cda9b8184a5d16a543ba482dfaa1a90d3e71d9903c19b667bd202f5b18
[haytok@lima-finch workspace]$ sudo nerdctl ps
CONTAINER ID    IMAGE                              COMMAND                   CREATED          STATUS    PORTS    NAMES
54f605cda9b8    docker.io/library/alpine:latest    "sh -c while true; d…"    3 seconds ago    Up                 test
[haytok@lima-finch workspace]$ sudo nerdctl attach test
FATA[0000] failed to attach to the container: failed to open stdout fifo: error creating fifo binary:///usr/local/bin/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59: no such file or directory
```

ここで発生したエラーメッセージ `failed to attach to the container: failed to open stdout fifo: error creating fifo binary:///usr/local/bin/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59: no such file or directory` を元に、エラーが発生する過程を追います。

```bash
[haytok@lima-default nerdctl]$ grep -rn "failed to attach to the container" . -B2 -A1
grep: ./_output/nerdctl: binary file matches
--
./pkg/cmd/container/attach.go-96-	task, err = container.Task(ctx, cio.NewAttach(opt))
./pkg/cmd/container/attach.go-97-	if err != nil {
./pkg/cmd/container/attach.go:98:		return fmt.Errorf("failed to attach to the container: %w", err)
./pkg/cmd/container/attach.go-99-	}
```

`container.Task()` の実装を追うために、containerd のリポジトリを確認する。

```bash
[haytok@lima-default containerd]$ grep -rn ") Task(" . -A2
./container.go:190:func (c *container) Task(ctx context.Context, attach cio.Attach) (Task, error) {
./container.go-191-	return c.loadTask(ctx, attach)
./container.go-192-}
```

```bash
[haytok@lima-default containerd]$ grep -rn ") loadTask(" . -A29
./container.go:390:func (c *container) loadTask(ctx context.Context, ioAttach cio.Attach) (Task, error) {
./container.go-391-	fmt.Printf("0: In loadTask\n")
./container.go-392-	response, err := c.client.TaskService().Get(ctx, &tasks.GetRequest{
./container.go-393-		ContainerID: c.id,
./container.go-394-	})
./container.go-395-	if err != nil {
./container.go-396-		err = errdefs.FromGRPC(err)
./container.go-397-		if errdefs.IsNotFound(err) {
./container.go-398-			return nil, fmt.Errorf("no running task found: %w", err)
./container.go-399-		}
./container.go-400-		return nil, err
./container.go-401-	}
./container.go-402-	var i cio.IO
./container.go-403-	if ioAttach != nil && response.Process.Status != tasktypes.Status_UNKNOWN {
./container.go-404-		// Do not attach IO for task in unknown state, because there
./container.go-405-		// are no fifo paths anyway.
./container.go-406-		if i, err = attachExistingIO(response, ioAttach); err != nil {
./container.go-407-			fmt.Printf("1: In loadTask\n")
./container.go-408-			return nil, err
./container.go-409-		}
./container.go-410-	}
./container.go-411-	t := &task{
./container.go-412-		client: c.client,
./container.go-413-		io:     i,
./container.go-414-		id:     response.Process.ID,
./container.go-415-		pid:    response.Process.Pid,
./container.go-416-		c:      c,
./container.go-417-	}
./container.go-418-	return t, nil
./container.go-419-}
```

Check `attachExistingIO()`

```bash
[haytok@lima-default containerd]$ grep -rn "func attachExistingIO" . -A3
./container.go:426:func attachExistingIO(response *tasks.GetResponse, ioAttach cio.Attach) (cio.IO, error) {
./container.go-427-	fifoSet := loadFifos(response)
./container.go-428-	return ioAttach(fifoSet)
./container.go-429-}
```

`attachExistingIO()` 関数の返り値のエラーによって `failed to attach to the container: ...` のエラーが発生しているはずだが、エラーを返しうるのは `ioAttach()` しかない。

`ioAttach()` は `container.Task(ctx, cio.NewAttach(opt))` を呼び出す際の第二引数が実態なので、その実装を追っていく。

```bash
./pkg/cmd/container/attach.go-96-	task, err = container.Task(ctx, cio.NewAttach(opt))
```

引き続き、どの処理が error を返しうるかの観点から実装を追っていく。

```bash
[haytok@lima-default containerd]$ grep -rn "func NewAttach(" . -A20
./cio/io.go:160:func NewAttach(opts ...Opt) Attach {
./cio/io.go-161-	streams := &Streams{}
./cio/io.go-162-	for _, opt := range opts {
./cio/io.go-163-		opt(streams)
./cio/io.go-164-	}
./cio/io.go-165-	return func(fifos *FIFOSet) (IO, error) {
./cio/io.go-166-		if fifos == nil {
./cio/io.go-167-			return nil, fmt.Errorf("cannot attach, missing fifos")
./cio/io.go-168-		}
./cio/io.go-169-		if streams.Stdin == nil {
./cio/io.go-170-			fifos.Stdin = ""
./cio/io.go-171-		}
./cio/io.go-172-		if streams.Stdout == nil {
./cio/io.go-173-			fifos.Stdout = ""
./cio/io.go-174-		}
./cio/io.go-175-		if streams.Stderr == nil {
./cio/io.go-176-			fifos.Stderr = ""
./cio/io.go-177-		}
./cio/io.go-178-		return copyIO(fifos, streams)
./cio/io.go-179-	}
./cio/io.go-180-}
```

```bash
[haytok@lima-default containerd]$ grep -rn "func copyIO(" . -A6
./cio/io_windows.go:44:func copyIO(fifos *FIFOSet, ioset *Streams) (_ *cio, retErr error) {
./cio/io_windows.go-45-	cios := &cio{config: fifos.Config}
./cio/io_windows.go-46-
./cio/io_windows.go-47-	defer func() {
./cio/io_windows.go-48-		if retErr != nil {
./cio/io_windows.go-49-			_ = cios.Close()
./cio/io_windows.go-50-		}
--
./cio/io_unix.go:56:func copyIO(fifos *FIFOSet, ioset *Streams) (*cio, error) {
./cio/io_unix.go-57-	var ctx, cancel = context.WithCancel(context.Background())
./cio/io_unix.go-58-	pipes, err := openFifos(ctx, fifos)
./cio/io_unix.go-59-	if err != nil {
./cio/io_unix.go-60-		cancel()
./cio/io_unix.go-61-		return nil, err
./cio/io_unix.go-62-	}
```

windows の実装に関心はないので、unix の方の実装を追う。

```bash
[haytok@lima-default containerd]$ grep -rn "func openFifos(" . -A23
./cio/io_unix.go:113:func openFifos(ctx context.Context, fifos *FIFOSet) (f pipes, retErr error) {
./cio/io_unix.go-114-	defer func() {
./cio/io_unix.go-115-		if retErr != nil {
./cio/io_unix.go-116-			fifos.Close()
./cio/io_unix.go-117-		}
./cio/io_unix.go-118-	}()
./cio/io_unix.go-119-
./cio/io_unix.go-120-	if fifos.Stdin != "" {
./cio/io_unix.go-121-		if f.Stdin, retErr = fifo.OpenFifo(ctx, fifos.Stdin, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_NONBLOCK, 0700); retErr != nil {
./cio/io_unix.go-122-			return f, fmt.Errorf("failed to open stdin fifo: %w", retErr)
./cio/io_unix.go-123-		}
./cio/io_unix.go-124-		defer func() {
./cio/io_unix.go-125-			if retErr != nil && f.Stdin != nil {
./cio/io_unix.go-126-				f.Stdin.Close()
./cio/io_unix.go-127-			}
./cio/io_unix.go-128-		}()
./cio/io_unix.go-129-	}
./cio/io_unix.go-130-	if fifos.Stdout != "" {
./cio/io_unix.go-131-		if f.Stdout, retErr = fifo.OpenFifo(ctx, fifos.Stdout, syscall.O_RDONLY|syscall.O_CREAT|syscall.O_NONBLOCK, 0700); retErr != nil {
./cio/io_unix.go-132-			fmt.Printf("In openFifos, fifos.Stdout -> %s\n", fifos.Stdout)
./cio/io_unix.go-133-			fmt.Printf("In openFifos, fifos.Stdin -> %s\n", fifos.Stdin)
./cio/io_unix.go-134-			fmt.Printf("In openFifos, fifos.Stderr -> %s \n", fifos.Stderr)
./cio/io_unix.go-135-			return f, fmt.Errorf("failed to open stdout fifo: %w", retErr)
./cio/io_unix.go-136-		}
```

Check OpenFifo in fifo repository

```bash
[haytok@lima-default fifo]$ grep -rn "func OpenFifo(" *.go -A9
fifo.go:72:func OpenFifo(ctx context.Context, fn string, flag int, perm os.FileMode) (io.ReadWriteCloser, error) {
fifo.go-73-	fmt.Printf("0: In OpenFifo\n")
fifo.go-74-	fifo, err := openFifo(ctx, fn, flag, perm)
fifo.go-75-	if fifo == nil {
fifo.go-76-		// Do not return a non-nil ReadWriteCloser((*fifo)(nil)) value
fifo.go-77-		// as that can confuse callers.
fifo.go-78-		return nil, err
fifo.go-79-	}
fifo.go-80-	return fifo, err
fifo.go-81-}
```

Check fifo source code not nerdctl source code

```bash
[haytok@lima-default fifo]$ grep -rn "func openFifo(" *.go -A10
fifo.go:83:func openFifo(ctx context.Context, fn string, flag int, perm os.FileMode) (*fifo, error) {
fifo.go-84-	fmt.Printf("0: In openFifo, fn: %s\n", fn)
fifo.go-85-	if _, err := os.Stat(fn); err != nil {
fifo.go-86-		fmt.Printf("1: In openFifo\n")
fifo.go-87-		if os.IsNotExist(err) && flag&syscall.O_CREAT != 0 {
fifo.go-88-			fmt.Printf("2: In openFifo\n")
fifo.go-89-			if err := syscall.Mkfifo(fn, uint32(perm&os.ModePerm)); err != nil && !os.IsExist(err) {
fifo.go-90-				return nil, fmt.Errorf("error creating fifo %v: %w", fn, err)
fifo.go-91-			}
fifo.go-92-		} else {
fifo.go-93-			return nil, err
```

これでエラーの末端までたどり着いた。

おそらく、`syscall.Mkfifo(fn, uint32(perm&os.ModePerm))` の処理にこけてエラーが発生した。

`fn` には何が入っているかと、`syscall.Mkfifo()` を確認する。

上述の `fmt.Printf()` の Debug code を挿入した nerdctl を build して動作を確認する。

```bash
[haytok@lima-default nerdctl]$ alias | grep jake
alias jake='make -j $(nproc)'
[haytok@lima-default nerdctl]$ sudo ./_output/nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6
[haytok@lima-default nerdctl]$ sudo ./_output/nerdctl attach test
0: In loadTask
0: In OpenFifo
0: In openFifo, fn: binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59
1: In openFifo
2: In openFifo
In openFifos, fifos.Stdout -> binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59
In openFifos, fifos.Stdin ->
In openFifos, fifos.Stderr -> binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59
1: In loadTask
FATA[0000] failed to attach to the container: failed to open stdout fifo: error creating fifo binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59: no such file or directory
```

Debug メッセージ等を加味すると、fn (fifos.Stdout) に `binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59` が設定されていることによって、エラーになっている。

`1935db59` の値は一意に定まるハッシュ値の一部っぽい。

```bash
[haytok@lima-default nerdctl]$ echo $(echo -n "/run/containerd/containerd.sock" | sha256sum | cut -c1-8)
1935db59
```

詳細は下記の doc に書いてあった。

- https://github.com/containerd/nerdctl/blob/main/docs/dir.md

```bash
[haytok@lima-default nerdctl]$ sudo tree /var/lib/nerdctl/1935db59
/var/lib/nerdctl/1935db59
├── containers
│   └── default
│       ├── 31b73a05a787aae0314bf6e5302e64127e659f3b2913f47a4a181c12686b901e
│       │   ├── 31b73a05a787aae0314bf6e5302e64127e659f3b2913f47a4a181c12686b901e-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       ├── 3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6
│       │   ├── 3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   ├── oci-hook.startContainer.log
│       │   └── resolv.conf
│       ├── 371236edf6cfbd5290f43f5772527fd6d287daa8d04f1fac58e6fe49d0cdea1d
│       │   ├── 371236edf6cfbd5290f43f5772527fd6d287daa8d04f1fac58e6fe49d0cdea1d-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       ├── 8f2969effbf6fb0c8cd0358c03494c25d5bafd87c0aa1218861fe59e3d5e3550
│       │   ├── 8f2969effbf6fb0c8cd0358c03494c25d5bafd87c0aa1218861fe59e3d5e3550-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       ├── a4e8f622ce1004f2b7bb224d9b2ead3235c053c6f2443ee371cde09ec43c3150
│       │   ├── a4e8f622ce1004f2b7bb224d9b2ead3235c053c6f2443ee371cde09ec43c3150-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       ├── a6b1677b854c18a8cbc77bd52ce5f50a07bded07de4b5684d520653c676dd02e
│       │   ├── a6b1677b854c18a8cbc77bd52ce5f50a07bded07de4b5684d520653c676dd02e-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       ├── b261e00db083b63902acf7201a15183ba40e31f829d114287814eb679f70aeec
│       │   ├── b261e00db083b63902acf7201a15183ba40e31f829d114287814eb679f70aeec-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       ├── bfdb321d5dcf1ec7c0e900713597ba73d55efd7ae32d13e50bf776af66319c1a
│       │   ├── bfdb321d5dcf1ec7c0e900713597ba73d55efd7ae32d13e50bf776af66319c1a-json.log
│       │   ├── hostname
│       │   ├── log-config.json
│       │   └── resolv.conf
│       └── e56eee84f6a9ff827396e2d83c75657f51c1f31899bf3e0f53bc620bede508db
│           ├── e56eee84f6a9ff827396e2d83c75657f51c1f31899bf3e0f53bc620bede508db-json.log
│           ├── hostname
│           ├── log-config.json
│           └── resolv.conf
├── etchosts
│   └── default
│       ├── 31b73a05a787aae0314bf6e5302e64127e659f3b2913f47a4a181c12686b901e
│       │   └── hosts
│       ├── 3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6
│       │   ├── hosts
│       │   └── meta.json
│       ├── 371236edf6cfbd5290f43f5772527fd6d287daa8d04f1fac58e6fe49d0cdea1d
│       │   └── hosts
│       ├── 8f2969effbf6fb0c8cd0358c03494c25d5bafd87c0aa1218861fe59e3d5e3550
│       │   └── hosts
│       ├── a4e8f622ce1004f2b7bb224d9b2ead3235c053c6f2443ee371cde09ec43c3150
│       │   └── hosts
│       ├── a6b1677b854c18a8cbc77bd52ce5f50a07bded07de4b5684d520653c676dd02e
│       │   └── hosts
│       ├── b261e00db083b63902acf7201a15183ba40e31f829d114287814eb679f70aeec
│       │   └── hosts
│       ├── bfdb321d5dcf1ec7c0e900713597ba73d55efd7ae32d13e50bf776af66319c1a
│       │   └── hosts
│       └── e56eee84f6a9ff827396e2d83c75657f51c1f31899bf3e0f53bc620bede508db
│           └── hosts
├── names
│   └── default
│       └── test
└── volumes
    └── default
```

```bash
[haytok@lima-default nerdctl]$ sudo _output/nerdctl ps
CONTAINER ID    IMAGE                              COMMAND                   CREATED          STATUS    PORTS    NAMES
3209cc5c61e2    docker.io/library/alpine:latest    "sh -c while true; d…"    7 minutes ago    Up                 test
```

現時点で動かしているコンテナ ID と照らし合わせた感じ、`/var/lib/nerdctl/1935db59` の配下にコンテナに関連するデータが突っ込まれていると考えられる。

## 調査 2

...

## 調査 3

...


## 結論

...

## まとめ

SDE のトラシュー力に憧れて自分もコンテナに関連する OSS の開発により積極的に従事したくなった。いや、従事します。

## Misc

```bash
sudo ./_output/nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
sudo ./_output/nerdctl attach test
```
