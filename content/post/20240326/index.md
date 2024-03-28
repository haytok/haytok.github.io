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

## Summary

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
2. `sudo nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"` を実行した際動作の確認と workaround を調査する。
3. nerdctl 内で使用されているパッケージ fifo の動作を確認する。

## 調査 1 (nerdctl attach コマンドを実行した際に発生するエラーを突き止め、そのエラーが発生する条件を調査する。)

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

Check error message `failed to attach to the container`

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

Check `loadTask()`

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

`ioAttach()` は `container.Task(ctx, cio.NewAttach(opt))` を呼び出す際の第二引数が体なので、その実装を追っていく。

```bash
./pkg/cmd/container/attach.go-96-	task, err = container.Task(ctx, cio.NewAttach(opt))
```

引き続き、どの処理が error を返しうるかの観点から実装を追っていく。

Check `NewAttach()`

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

Check `copyIO`

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

Check `openFifos()`

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

Check `OpenFifo()` in fifo repository

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

Check `openFifo()` in fifo source code not nerdctl source code

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
[haytok@lima-default nerdctl]$ jake
GO111MODULE=on CGO_ENABLED=0 GOOS=linux go build -ldflags "-s -w -X github.com/containerd/nerdctl/v2/pkg/version.Version=78b66fdc.m -X github.com/containerd/nerdctl/v2/pkg/version.Revision=78b66fdcde0eeafb95fdf9915dc4ccbaef51021a.m"   -o /Users/haytok/workspace/nerdctl/_output/nerdctl github.com/containerd/nerdctl/v2/cmd/nerdctl
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

Debug メッセージ等を加味すると、fn (`fifos.Stdout`) に `binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59` が設定されていることによって、エラーになっている。

なお、-d コマンドでバックグラウンドでコンテナを起動し、その際に標準出力に吐き出すように実行したコマンド `sh -c while true; do echo /'Hello, world/'; sleep 1; done` の結果は `nerdctl logs <コンテナ名>` から確認できる log ファイルには吐き出されいていることが明らかになった。

エラーに関しては、`nerdctl run -d ...` でコンテナを起動しているので、`fifos.Stdout` に標準出力のファイルが指定されていないのではないかと考えられる。

一旦、比較するために `nerdctl run --name hoge --rm -it alpine sh` を実行した際に、`fifo.Stdout` に設定されるファイルを確認してみる。

```bash
[haytok@lima-default nerdctl]$ sudo _output/nerdctl run --name hoge --rm -it alpine sh
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/345658729/f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4-stdin
1: In openFifo
2: In openFifo
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/345658729/f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4-stdout
1: In openFifo
2: In openFifo
/ #
```

`-d` を指定せず `-it` オプションを指定してフォアグラウンドでコンテナを起動すると標準出力と標準入力にはそれ用のファイルが作成された。

```bash
[haytok@lima-default containerd]$ sudo ../nerdctl/_output/nerdctl ps
CONTAINER ID    IMAGE                              COMMAND                   CREATED          STATUS    PORTS    NAMES
3209cc5c61e2    docker.io/library/alpine:latest    "sh -c while true; d…"    22 hours ago     Up                 test
f26c33cf3499    docker.io/library/alpine:latest    "sh"                      2 minutes ago    Up                 hoge
[haytok@lima-default containerd]$ sudo ../nerdctl/_output/nerdctl ps --no-trunc
CONTAINER ID                                                        IMAGE                              COMMAND                                                        CREATED          STATUS    PORTS    NAMES
3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6    docker.io/library/alpine:latest    "sh -c while true; do echo /'Hello, world/'; sleep 1; done"    22 hours ago     Up                 test
f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4    docker.io/library/alpine:latest    "sh"                                                           2 minutes ago    Up                 hoge
```

`345658729` の値は何かわからんけど、その配下にコンテナ hoge に関連するデータが配置されている。

```bash
[haytok@lima-default containerd]$ sudo ls -la  /run/containerd/fifo/345658729/
total 0
drwx------.  2 root root  80 Mar 27 22:03 .
drwx------. 11 root root 220 Mar 27 22:03 ..
prwx------.  1 root root   0 Mar 27 22:09 f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4-stdin
prwx------.  1 root root   0 Mar 27 22:09 f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4-stdout
```

stdout と stdin のためのパイプが作成されている。

一方、`-d` でコンテナを起動する前後での `/run/containerd/fifo` 配下のディレクトリ構成の違いを確認したところ、差はなかった。

```bash
[haytok@lima-default containerd]$ sudo ls /run/containerd/fifo
118231144  2164213081  2376111114  2554841498  313929042  345658729  3541429126  890640757  938856586

# run sudo ./_output/nerdctl run --name testtest -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"

[haytok@lima-default containerd]$ sudo ls /run/containerd/fifo
118231144  2164213081  2376111114  2554841498  313929042  345658729  3541429126  890640757  938856586
```

なので、`-d` の時は fifo のパイプのファイルが作成されない処理を追ってみる。

つまり、`nerdctl run` の処理を追う。

ディレクトリ構成的に `nerdctl/cmd/nerdctl/container_run.go` 内の処理が `nerdctl run` 時に呼び出されるはず。

```bash
haytok ~/workspace/nerdctl [main]
> git diff cmd/nerdctl/container_run.go
diff --git a/cmd/nerdctl/container_run.go b/cmd/nerdctl/container_run.go
index 077332d4..a059b504 100644
--- a/cmd/nerdctl/container_run.go
+++ b/cmd/nerdctl/container_run.go
@@ -373,6 +373,7 @@ func runAction(cmd *cobra.Command, args []string) error {
        }
        logURI := lab[labels.LogURI]
        detachC := make(chan struct{})
+       fmt.Printf("0: In runAction\n")
        task, err := taskutil.NewTask(ctx, client, c, false, createOpt.Interactive, createOpt.TTY, createOpt.Detach,
                con, logURI, createOpt.DetachKeys, createOpt.GOptions.Namespace, detachC)
        if err != nil {
```

build して確認したところ、予想通りやった。

```bash
[haytok@lima-default nerdctl]$ sudo ./_output/nerdctl run --name testtest -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
04445d3aef8f12697ea975d78cc7ff831a27afa3140107a59ca5006530c23525
[haytok@lima-default nerdctl]$ jake
GO111MODULE=on CGO_ENABLED=0 GOOS=linux go build -ldflags "-s -w -X github.com/containerd/nerdctl/v2/pkg/version.Version=78b66fdc.m -X github.com/containerd/nerdctl/v2/pkg/version.Revision=78b66fdcde0eeafb95fdf9915dc4ccbaef51021a.m"   -o /Users/haytok/workspace/nerdctl/_output/nerdctl github.com/containerd/nerdctl/v2/cmd/nerdctl
[haytok@lima-default nerdctl]$ sudo _output/nerdctl run --name hoge --rm -it alpine sh
0: In runAction
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/1034591092/80976a1afcadac0ab011154709e64522ee60f068cd46ff0aa3322bc10a72e54f-stdin
1: In openFifo
2: In openFifo
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/1034591092/80976a1afcadac0ab011154709e64522ee60f068cd46ff0aa3322bc10a72e54f-stdout
1: In openFifo
2: In openFifo
/ #
```

なので、以降は `runAction()` 内の処理を追っていく。

特に、下記の処理が重要そうなので、`NewTask()` の処理を確認する。

```golang
	task, err := taskutil.NewTask(ctx, client, c, false, createOpt.Interactive, createOpt.TTY, createOpt.Detach,
		con, logURI, createOpt.DetachKeys, createOpt.GOptions.Namespace, detachC)
	if err != nil {
		return err
	}
	if err := task.Start(ctx); err != nil {
		return err
	}
```

Check `NewTask()`

```bash
[haytok@lima-default nerdctl]$ grep -rn " NewTask(" -A120
pkg/taskutil/taskutil.go:42:func NewTask(ctx context.Context, client *containerd.Client, container containerd.Container,
pkg/taskutil/taskutil.go-43-	flagA, flagI, flagT, flagD bool, con console.Console, logURI, detachKeys, namespace string, detachC chan<- struct{}) (containerd.Task, error) {
pkg/taskutil/taskutil.go-44-	var t containerd.Task
pkg/taskutil/taskutil.go-45-	fmt.Printf("0: In, NewTask\n")
pkg/taskutil/taskutil.go-46-	closer := func() {
pkg/taskutil/taskutil.go-47-		if detachC != nil {
pkg/taskutil/taskutil.go-48-			detachC <- struct{}{}
pkg/taskutil/taskutil.go-49-		}
pkg/taskutil/taskutil.go-50-		// t will be set by container.NewTask at the end of this function.
pkg/taskutil/taskutil.go-51-		//
pkg/taskutil/taskutil.go-52-		// We cannot use container.Task(ctx, cio.Load) to get the IO here
pkg/taskutil/taskutil.go-53-		// because the `cancel` field of the returned `*cio` is nil. [1]
pkg/taskutil/taskutil.go-54-		//
pkg/taskutil/taskutil.go-55-		// [1] https://github.com/containerd/containerd/blob/8f756bc8c26465bd93e78d9cd42082b66f276e10/cio/io.go#L358-L359
pkg/taskutil/taskutil.go-56-		io := t.IO()
pkg/taskutil/taskutil.go-57-		if io == nil {
pkg/taskutil/taskutil.go-58-			log.G(ctx).Errorf("got a nil io")
pkg/taskutil/taskutil.go-59-			return
pkg/taskutil/taskutil.go-60-		}
pkg/taskutil/taskutil.go-61-		io.Cancel()
pkg/taskutil/taskutil.go-62-	}
pkg/taskutil/taskutil.go-63-	var ioCreator cio.Creator
pkg/taskutil/taskutil.go-64-	if flagA {
pkg/taskutil/taskutil.go-65-		fmt.Printf("1: In, NewTask\n")
pkg/taskutil/taskutil.go-66-		log.G(ctx).Debug("attaching output instead of using the log-uri")
pkg/taskutil/taskutil.go-67-		if flagT {
pkg/taskutil/taskutil.go-68-			in, err := consoleutil.NewDetachableStdin(con, detachKeys, closer)
pkg/taskutil/taskutil.go-69-			if err != nil {
pkg/taskutil/taskutil.go-70-				return nil, err
pkg/taskutil/taskutil.go-71-			}
pkg/taskutil/taskutil.go-72-			ioCreator = cio.NewCreator(cio.WithStreams(in, con, nil), cio.WithTerminal)
pkg/taskutil/taskutil.go-73-		} else {
pkg/taskutil/taskutil.go-74-			ioCreator = cio.NewCreator(cio.WithStdio)
pkg/taskutil/taskutil.go-75-		}
pkg/taskutil/taskutil.go-76-
pkg/taskutil/taskutil.go-77-	} else if flagT && flagD {
pkg/taskutil/taskutil.go-78-		fmt.Printf("2: In, NewTask\n")
pkg/taskutil/taskutil.go-79-		u, err := url.Parse(logURI)
pkg/taskutil/taskutil.go-80-		if err != nil {
pkg/taskutil/taskutil.go-81-			return nil, err
pkg/taskutil/taskutil.go-82-		}
pkg/taskutil/taskutil.go-83-
pkg/taskutil/taskutil.go-84-		var args []string
pkg/taskutil/taskutil.go-85-		for k, vs := range u.Query() {
pkg/taskutil/taskutil.go-86-			args = append(args, k)
pkg/taskutil/taskutil.go-87-			if len(vs) > 0 {
pkg/taskutil/taskutil.go-88-				args = append(args, vs[0])
pkg/taskutil/taskutil.go-89-			}
pkg/taskutil/taskutil.go-90-		}
pkg/taskutil/taskutil.go-91-
pkg/taskutil/taskutil.go-92-		// args[0]: _NERDCTL_INTERNAL_LOGGING
pkg/taskutil/taskutil.go-93-		// args[1]: /var/lib/nerdctl/1935db59
pkg/taskutil/taskutil.go-94-		fmt.Printf("0: In NewTask, args: %#v", args)
pkg/taskutil/taskutil.go-95-		if len(args) != 2 {
pkg/taskutil/taskutil.go-96-			return nil, errors.New("parse logging path error")
pkg/taskutil/taskutil.go-97-		}
pkg/taskutil/taskutil.go-98-		ioCreator = cio.TerminalBinaryIO(u.Path, map[string]string{
pkg/taskutil/taskutil.go-99-			args[0]: args[1],
pkg/taskutil/taskutil.go-100-		})
pkg/taskutil/taskutil.go-101-	} else if flagT && !flagD {
pkg/taskutil/taskutil.go-102-		fmt.Printf("3: In, NewTask\n")
pkg/taskutil/taskutil.go-103-
pkg/taskutil/taskutil.go-104-		if con == nil {
pkg/taskutil/taskutil.go-105-			return nil, errors.New("got nil con with flagT=true")
pkg/taskutil/taskutil.go-106-		}
pkg/taskutil/taskutil.go-107-		var in io.Reader
pkg/taskutil/taskutil.go-108-		if flagI {
pkg/taskutil/taskutil.go-109-			// FIXME: check IsTerminal on Windows too
pkg/taskutil/taskutil.go-110-			if runtime.GOOS != "windows" && !term.IsTerminal(0) {
pkg/taskutil/taskutil.go-111-				return nil, errors.New("the input device is not a TTY")
pkg/taskutil/taskutil.go-112-			}
pkg/taskutil/taskutil.go-113-			var err error
pkg/taskutil/taskutil.go-114-			in, err = consoleutil.NewDetachableStdin(con, detachKeys, closer)
pkg/taskutil/taskutil.go-115-			if err != nil {
pkg/taskutil/taskutil.go-116-				return nil, err
pkg/taskutil/taskutil.go-117-			}
pkg/taskutil/taskutil.go-118-		}
pkg/taskutil/taskutil.go-119-		ioCreator = cioutil.NewContainerIO(namespace, logURI, true, in, os.Stdout, os.Stderr)
pkg/taskutil/taskutil.go-120-	} else if flagD {
pkg/taskutil/taskutil.go-121-		fmt.Printf("4: In, NewTask\n")
pkg/taskutil/taskutil.go-122-		ioCreator = cio.NewCreator(cio.WithStdio)
pkg/taskutil/taskutil.go-123-	} else if flagD && logURI != "" {
pkg/taskutil/taskutil.go-124-		fmt.Printf("44: In, NewTask, logURI: %s, flagD: %b\n", logURI, flagD)
pkg/taskutil/taskutil.go-125-		// sudo ./_output/nerdctl run --name test2 -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
pkg/taskutil/taskutil.go-126-		// を実行した時は。この if 文に処理が実施される。
pkg/taskutil/taskutil.go-127-
pkg/taskutil/taskutil.go-128-		u, err := url.Parse(logURI)
pkg/taskutil/taskutil.go-129-		if err != nil {
pkg/taskutil/taskutil.go-130-			return nil, err
pkg/taskutil/taskutil.go-131-		}
pkg/taskutil/taskutil.go-132-		fmt.Printf("444: In, NewTask, u: %#v\n", u)
pkg/taskutil/taskutil.go-133-		ioCreator = cio.LogURI(u)
pkg/taskutil/taskutil.go-134-	} else {
pkg/taskutil/taskutil.go-135-		fmt.Printf("5: In, NewTask, flagT && !flagD\n")
pkg/taskutil/taskutil.go-136-		var in io.Reader
pkg/taskutil/taskutil.go-137-		if flagI {
pkg/taskutil/taskutil.go-138-			if sv, err := infoutil.ServerSemVer(ctx, client); err != nil {
pkg/taskutil/taskutil.go-139-				log.G(ctx).Warn(err)
pkg/taskutil/taskutil.go-140-			} else if sv.LessThan(semver.MustParse("1.6.0-0")) {
pkg/taskutil/taskutil.go-141-				log.G(ctx).Warnf("`nerdctl (run|exec) -i` without `-t` expects containerd 1.6 or later, got containerd %v", sv)
pkg/taskutil/taskutil.go-142-			}
pkg/taskutil/taskutil.go-143-			var stdinC io.ReadCloser = &StdinCloser{
pkg/taskutil/taskutil.go-144-				Stdin: os.Stdin,
pkg/taskutil/taskutil.go-145-				Closer: func() {
pkg/taskutil/taskutil.go-146-					if t, err := container.Task(ctx, nil); err != nil {
pkg/taskutil/taskutil.go-147-						log.G(ctx).WithError(err).Debugf("failed to get task for StdinCloser")
pkg/taskutil/taskutil.go-148-					} else {
pkg/taskutil/taskutil.go-149-						t.CloseIO(ctx, containerd.WithStdinCloser)
pkg/taskutil/taskutil.go-150-					}
pkg/taskutil/taskutil.go-151-				},
pkg/taskutil/taskutil.go-152-			}
pkg/taskutil/taskutil.go-153-			in = stdinC
pkg/taskutil/taskutil.go-154-		}
pkg/taskutil/taskutil.go-155-		ioCreator = cioutil.NewContainerIO(namespace, logURI, false, in, os.Stdout, os.Stderr)
pkg/taskutil/taskutil.go-156-	}
pkg/taskutil/taskutil.go-157-	t, err := container.NewTask(ctx, ioCreator)
pkg/taskutil/taskutil.go-158-	if err != nil {
pkg/taskutil/taskutil.go-159-		return nil, err
pkg/taskutil/taskutil.go-160-	}
pkg/taskutil/taskutil.go-161-	return t, nil
pkg/taskutil/taskutil.go-162-}
```

ここでやっと [Shubhranshu153 ]() が言及していた処理が出てきた！！！

[Shubhranshu153]() の指摘にあるように、下記のコードを足して動作確認してみる。

確認する際は nerdctl を rebuild して、再度コンテナを起動させる。

```bash
haytok ~/workspace/nerdctl [main]
> git diff pkg/
diff --git a/pkg/taskutil/taskutil.go b/pkg/taskutil/taskutil.go
index 101452f8..3ca063d1 100644
--- a/pkg/taskutil/taskutil.go
+++ b/pkg/taskutil/taskutil.go
...
@@ -111,13 +117,22 @@ func NewTask(ctx context.Context, client *containerd.Client, container container
                        }
                }
                ioCreator = cioutil.NewContainerIO(namespace, logURI, true, in, os.Stdout, os.Stderr)
+       } else if flagD {
+               fmt.Printf("4: In, NewTask\n")
+               ioCreator = cio.NewCreator(cio.WithStdio)
        } else if flagD && logURI != "" {
...
```

そうすると、確かに -d で起動したコンテナに `nerdctl attach` することができた。

```bash
[haytok@lima-default nerdctl]$ sudo ./_output/nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
0: In runAction
0: In, NewTask
4: In, NewTask
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/3201500946/40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b-stdin
1: In openFifo
2: In openFifo
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/3201500946/40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b-stdout
1: In openFifo
2: In openFifo
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/3201500946/40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b-stderr
1: In openFifo
2: In openFifo
/Hello, world/
40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b
[haytok@lima-default nerdctl]$ sudo ./_output/nerdctl attach test
0: In loadTask
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/3201500946/40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b-stdin
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/3201500946/40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b-stdout
0: In OpenFifo
0: In openFifo, fn: /run/containerd/fifo/3201500946/40589e0394da21a578fc5767b92b3aac8333dea55fdcd0b531e5d772c7f8793b-stderr
/Hello, world/
/Hello, world/
/Hello, world/
```

```bash
[haytok@lima-default nerdctl]$ sudo ./_output/nerdctl ps --no-trunc
0: In loadTask
0: In loadTask
0: In loadTask
0: In loadTask
CONTAINER ID                                                        IMAGE                              COMMAND                                                        CREATED               STATUS    PORTS    NAMES
04445d3aef8f12697ea975d78cc7ff831a27afa3140107a59ca5006530c23525    docker.io/library/alpine:latest    "sh -c while true; do echo /'Hello, world/'; sleep 1; done"    20 minutes ago        Up                 testtest
a074368ed3103fa9ce8e1b4b2e366bfc85b90a200b8d33b5db9bb8befaebfa0f    docker.io/library/alpine:latest    "sh -c while true; do echo /'Hello, world/'; sleep 1; done"    About a minute ago    Up                 test
[haytok@lima-default containerd]$ sudo tree -L 2  /run/containerd/fifo
/run/containerd/fifo
├── 1034591092
│   ├── 80976a1afcadac0ab011154709e64522ee60f068cd46ff0aa3322bc10a72e54f-stdin
│   └── 80976a1afcadac0ab011154709e64522ee60f068cd46ff0aa3322bc10a72e54f-stdout
├── 118231144
│   ├── 1ae9c69f9ee18e2263455c41cb9162c4608934cb76b3eb65f26ea7cb0a5064ea-stdin
│   └── 1ae9c69f9ee18e2263455c41cb9162c4608934cb76b3eb65f26ea7cb0a5064ea-stdout
├── 2164213081
├── 2376111114
│   ├── 95e8262aedb39d0900968195ec65db649c917f369fcbb68475b163fbf820515d-stdin
│   └── 95e8262aedb39d0900968195ec65db649c917f369fcbb68475b163fbf820515d-stdout
├── 2439977144
│   ├── a074368ed3103fa9ce8e1b4b2e366bfc85b90a200b8d33b5db9bb8befaebfa0f-stderr
│   ├── a074368ed3103fa9ce8e1b4b2e366bfc85b90a200b8d33b5db9bb8befaebfa0f-stdin
│   └── a074368ed3103fa9ce8e1b4b2e366bfc85b90a200b8d33b5db9bb8befaebfa0f-stdout
├── 2554841498
│   ├── b5a6199c3cc4f2409e09e2410d8038d3108ca234f64090108c788f35c9b1f0b5-stdin
│   └── b5a6199c3cc4f2409e09e2410d8038d3108ca234f64090108c788f35c9b1f0b5-stdout
├── 313929042
├── 345658729
│   ├── f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4-stdin
│   └── f26c33cf34999edf45ab3306aa074b7496671cb8bfcd9a6d870623cbeec11be4-stdout
├── 3541429126
│   ├── 838f295c4635acb3a06e4d5a81ed49d84f1dfb0fa532666089477eb6e70ad3d0-stdin
│   └── 838f295c4635acb3a06e4d5a81ed49d84f1dfb0fa532666089477eb6e70ad3d0-stdout
├── 890640757
└── 938856586
    ├── affc6c7417229c0d15f43eb2d8f0322cdd7737c5953fe5d079b08cd0f1862593-stdin
    └── affc6c7417229c0d15f43eb2d8f0322cdd7737c5953fe5d079b08cd0f1862593-stdout

12 directories, 17 files
[haytok@lima-default containerd]$ sudo cat /run/containerd/fifo/2439977144/a074368ed3103fa9ce8e1b4b2e366bfc85b90a200b8d33b5db9bb8befaebfa0f-stdout
/Hello, world/
/Hello, world/
/Hello, world/
...
```

以上から、`nerdctl run` を実行し、`-d` オプションのみを指定した時でも stdin / stdout / stderr 用の fifo を作成するようにロジックを変更すると、とりあえず `-d` で起動したコンテナに `nerdctl attach` を実行することはできる。

## 調査 2 (`sudo nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"` を実行した際動作の確認と workaround を調査する。)

コンテナを起動する際のオプションの組み合わせの動作を確認してみる。

- https://github.com/containerd/nerdctl/blob/main/pkg/taskutil/taskutil.go#L41-L147

logURI に文字列が挿入される状況が不明

```golang
// NewTask is from https://github.com/containerd/containerd/blob/v1.4.3/cmd/ctr/commands/tasks/tasks_unix.go#L70-L108
func NewTask(ctx context.Context, client *containerd.Client, container containerd.Container,
	flagA, flagI, flagT, flagD bool, con console.Console, logURI, detachKeys, namespace string, detachC chan<- struct{}) (containerd.Task, error) {
	var t containerd.Task
	fmt.Printf("0: In, NewTask\n")
	closer := func() {
		if detachC != nil {
			detachC <- struct{}{}
		}
		// t will be set by container.NewTask at the end of this function.
		//
		// We cannot use container.Task(ctx, cio.Load) to get the IO here
		// because the `cancel` field of the returned `*cio` is nil. [1]
		//
		// [1] https://github.com/containerd/containerd/blob/8f756bc8c26465bd93e78d9cd42082b66f276e10/cio/io.go#L358-L359
		io := t.IO()
		if io == nil {
			log.G(ctx).Errorf("got a nil io")
			return
		}
		io.Cancel()
	}
	var ioCreator cio.Creator
	if flagA {
		fmt.Printf("1: In, NewTask\n")
		log.G(ctx).Debug("attaching output instead of using the log-uri")
		if flagT {
			in, err := consoleutil.NewDetachableStdin(con, detachKeys, closer)
			if err != nil {
				return nil, err
			}
			ioCreator = cio.NewCreator(cio.WithStreams(in, con, nil), cio.WithTerminal)
		} else {
			ioCreator = cio.NewCreator(cio.WithStdio)
		}

	} else if flagT && flagD {
		fmt.Printf("2: In, NewTask\n")
		u, err := url.Parse(logURI)
		if err != nil {
			return nil, err
		}

		var args []string
		for k, vs := range u.Query() {
			args = append(args, k)
			if len(vs) > 0 {
				args = append(args, vs[0])
			}
		}

		// args[0]: _NERDCTL_INTERNAL_LOGGING
		// args[1]: /var/lib/nerdctl/1935db59
		fmt.Printf("0: In NewTask, args: %#v\n", args)
		if len(args) != 2 {
			return nil, errors.New("parse logging path error")
		}
		ioCreator = cio.TerminalBinaryIO(u.Path, map[string]string{
			args[0]: args[1],
		})
	} else if flagT && !flagD {
		fmt.Printf("3: In, NewTask\n")

		if con == nil {
			return nil, errors.New("got nil con with flagT=true")
		}
		var in io.Reader
		if flagI {
			// FIXME: check IsTerminal on Windows too
			if runtime.GOOS != "windows" && !term.IsTerminal(0) {
				return nil, errors.New("the input device is not a TTY")
			}
			var err error
			in, err = consoleutil.NewDetachableStdin(con, detachKeys, closer)
			if err != nil {
				return nil, err
			}
		}
		ioCreator = cioutil.NewContainerIO(namespace, logURI, true, in, os.Stdout, os.Stderr)
	} else if flagD {
		fmt.Printf("4: In, NewTask\n")
		ioCreator = cio.NewCreator(cio.WithStdio)
	} else if flagD && logURI != "" {
		fmt.Printf("44: In, NewTask, logURI: %s, flagD: %b\n", logURI, flagD)
		// sudo ./_output/nerdctl run --name test2 -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
		// を実行した時は。この if 文に処理が実施される。

		u, err := url.Parse(logURI)
		if err != nil {
			return nil, err
		}
		fmt.Printf("444: In, NewTask, u: %#v\n", u)
		ioCreator = cio.LogURI(u)
	} else {
		fmt.Printf("5: In, NewTask, flagT && !flagD\n")
		var in io.Reader
		if flagI {
			if sv, err := infoutil.ServerSemVer(ctx, client); err != nil {
				log.G(ctx).Warn(err)
			} else if sv.LessThan(semver.MustParse("1.6.0-0")) {
				log.G(ctx).Warnf("`nerdctl (run|exec) -i` without `-t` expects containerd 1.6 or later, got containerd %v", sv)
			}
			var stdinC io.ReadCloser = &StdinCloser{
				Stdin: os.Stdin,
				Closer: func() {
					if t, err := container.Task(ctx, nil); err != nil {
						log.G(ctx).WithError(err).Debugf("failed to get task for StdinCloser")
					} else {
						t.CloseIO(ctx, containerd.WithStdinCloser)
					}
				},
			}
			in = stdinC
		}
		ioCreator = cioutil.NewContainerIO(namespace, logURI, false, in, os.Stdout, os.Stderr)
	}
	t, err := container.NewTask(ctx, ioCreator)
	if err != nil {
		return nil, err
	}
	return t, nil
}
```

binary: のファイルの指定がよくわからんが、log-driver と関連がありそうなので、明日はそれを調査してみる。

## 調査 3 (nerdctl 内で使用されているパッケージ fifo の動作を確認する。)

...

## 結論

...

## まとめ

SDE のトラシュー力に憧れて自分もコンテナに関連する OSS の開発により積極的に従事したくなった。いや、従事します。

## Misc 1

`binary:///Users/haytok/workspace/nerdctl/_output/nerdctl?_NERDCTL_INTERNAL_LOGGING=%2Fvar%2Flib%2Fnerdctl%2F1935db59` における `1935db59` の値は一意に定まるハッシュ値の一部っぽい。

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

もう少し、`/var/lib/nerdctl/1935db59/containers/default/` に関して調査してみる。

今、バックグラウンドで起動しているコンテナ ID のフルは下記より確認できる。

```bash
[haytok@lima-default nerdctl]$ sudo _output/nerdctl ps --no-trunc
0: In loadTask
0: In loadTask
CONTAINER ID                                                        IMAGE                              COMMAND                                                        CREATED              STATUS    PORTS    NAMES
3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6    docker.io/library/alpine:latest    "sh -c while true; do echo /'Hello, world/'; sleep 1; done"    About an hour ago    Up                 test
```

このコンテナ ID がついた json log を確認すると、コンテナを起動する際に `sh -c` で指定したコマンドによる標準出力の結果が書き込まれていた。

```bash
[haytok@lima-default nerdctl]$ sudo head -5 /var/lib/nerdctl/1935db59/containers/default/3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6/3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6-json.log
{"log":"/Hello, world/\n","stream":"stdout","time":"2024-03-26T14:45:56.643460042Z"}
{"log":"/Hello, world/\n","stream":"stdout","time":"2024-03-26T14:45:57.647806795Z"}
{"log":"/Hello, world/\n","stream":"stdout","time":"2024-03-26T14:45:58.650546172Z"}
{"log":"/Hello, world/\n","stream":"stdout","time":"2024-03-26T14:45:59.65744747Z"}
{"log":"/Hello, world/\n","stream":"stdout","time":"2024-03-26T14:46:00.664010059Z"}
```

これ、このコンテナに exec して `echo haytok` を実行すると、この log の内容が変わるかを確認してみる。
結果、log には `echo haytok` による記録は確認することができなかった。

一方、下記のようにコンテナを起動し、標準出力に文字列を書き込むコマンドを実行したとする。

```bash
[haytok@lima-default nerdctl]$ sudo _output/nerdctl run --rm -it alpine sh
/ # echo hoge
hoge
/ # ls
bin    dev    etc    home   lib    media  mnt    opt    proc   root   run    sbin   srv    sys    tmp    usr    var
/ # echo risa
risa
/ #
```

```bash
[haytok@lima-default containerd]$ sudo ../nerdctl/_output/nerdctl ps --no-trunc
CONTAINER ID                                                        IMAGE                              COMMAND                                                        CREATED          STATUS    PORTS    NAMES
3209cc5c61e2adebd56cfa3a020e312a364d4faa934daa1c69252cdaed3d2ec6    docker.io/library/alpine:latest    "sh -c while true; do echo /'Hello, world/'; sleep 1; done"    2 hours ago      Up                 test
b5a6199c3cc4f2409e09e2410d8038d3108ca234f64090108c788f35c9b1f0b5    docker.io/library/alpine:latest    "sh"                                                           4 minutes ago    Up                 alpine-b5a61
[haytok@lima-default containerd]$ sudo cat /var/lib/nerdctl/1935db59/containers/default/b5a6199c3cc4f2409e09e2410d8038d3108ca234f64090108c788f35c9b1f0b5/b5a6199c3cc4f2409e09e2410d8038d3108ca234f64090108c788f35c9b1f0b5-json.log
{"log":"/ # \u001b[6n\r/ # \u001b[Jecho hoge\n","stream":"stdout","time":"2024-03-26T16:25:47.252472554Z"}
{"log":"hoge\n","stream":"stdout","time":"2024-03-26T16:25:47.25396863Z"}
{"log":"/ # \u001b[6nls\n","stream":"stdout","time":"2024-03-26T16:26:01.943442994Z"}
{"log":"\u001b[1;34mbin\u001b[m    \u001b[1;34mdev\u001b[m    \u001b[1;34metc\u001b[m    \u001b[1;34mhome\u001b[m   \u001b[1;34mlib\u001b[m    \u001b[1;34mmedia\u001b[m  \u001b[1;34mmnt\u001b[m    \u001b[1;34mopt\u001b[m    \u001b[1;34mproc\u001b[m   \u001b[1;34mroot\u001b[m   \u001b[1;34mrun\u001b[m    \u001b[1;34msbin\u001b[m   \u001b[1;34msrv\u001b[m    \u001b[1;34msys\u001b[m    \u001b[1;34mtmp\u001b[m    \u001b[1;34musr\u001b[m    \u001b[1;34mvar\u001b[m\n","stream":"stdout","time":"2024-03-26T16:26:01.948172886Z"}
{"log":"/ # \u001b[6n\r/ # ls\u001b[J\r/ # echo hoge\u001b[J\u0008\u001b[J\u0008\u001b[J\u0008\u001b[J\u0008\u001b[Jrisa\n","stream":"stdout","time":"2024-03-26T16:26:24.657328604Z"}
{"log":"risa\n","stream":"stdout","time":"2024-03-26T16:26:24.657492812Z"}
```

`-d` で動作させる時とそうでない時で動作が変わってそう。

Docker でも動作確認をしたけど、-d でコンテナを起動した時に、そのコンテナで echo hoge をしても log には書き込まれへんのは期待された動作っぽい？？？

## Misc 2

syscall.Mkfifo() について調査してみる。

そもそも、パイプを作成するためのコマンド / システムコールがある。

```bash
MKFIFO(1)                                                                         General Commands Manual                                                                        MKFIFO(1)

NAME
     mkfifo – make fifos

SYNOPSIS
     mkfifo [-m mode] fifo_name ...

DESCRIPTION
     The mkfifo utility creates the fifos requested, in the order specified.

     The options are as follows:

     -m      Set the file permission bits of the created fifos to the specified mode, ignoring the umask(2) of the calling process.  The mode argument takes any format that can be
             specified to the chmod(1) command.  If a symbolic mode is specified, the op symbols ‘+’ (plus) and ‘-’ (hyphen) are interpreted relative to an assumed initial mode of “a=rw”
             (read and write permissions for all).

     If the -m option is not specified, fifos are created with mode 0666 modified by the umask(2) of the calling process.  The mkfifo utility requires write permission in the parent
     directory.
```

```bash
haytok ~/workspace/verification/fifo-verification
> mkfifo fifo
haytok ~/workspace/verification/fifo-verification
> ls -la
total 24
drwxr-xr-x@ 6 haytok  staff   192  3 27 12:15 .
drwxr-xr-x@ 3 haytok  staff    96  3 23 20:15 ..
prw-r--r--@ 1 haytok  staff     0  3 27 12:15 fifo
-rw-r--r--@ 1 haytok  staff   133  3 23 20:16 go.mod
-rw-r--r--@ 1 haytok  staff   322  3 23 20:16 go.sum
-rw-r--r--@ 1 haytok  staff  1418  3 25 13:22 main.go
```

```bash
haytok ~/workspace/verification/fifo-verification
> echo haytok >> fifo
```

```bash
haytok ~/workspace/verification/fifo-verification
> cat fifo
haytok
```

- https://www.sambaiz.net/article/87/
- https://qiita.com/richmikan@github/items/bb660a58690ac01ec295

> 実はこれがmkfifoコマンドで作った不思議なファイル、「名前付きパイプ」の挙動です。
>
> 1. 名前付きパイプから読み出そうとすると、誰かがその名前付きパイプに書き込むまで待たされる。
> 2. 名前付きパイプへ書き込もうとすると、誰かがその名前付きパイプから読み出すまで待たされる。

## Other

重要なコマンド

```bash
sudo ./_output/nerdctl run --name test -d alpine sh -c "while true; do echo /'Hello, world/'; sleep 1; done"
sudo ./_output/nerdctl attach test
```
