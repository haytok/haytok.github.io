---
draft: true
title: "Linux Kernel Code Reading ..."
date: 2024-02-14T01:16:33+09:00
tags: ["Linux"]
pinned: false
ogimage: "img/images/20240214.png"
---

## Overview

以前、下記のプログラムで HTTP Server を実装した。

- https://github.com/haytok/http-server/blob/main/c/http.c#L131

その際に、socket() システムコールは下記のように呼び出しを行った。

```bash
s = socket(AF_INET, SOCK_STREAM, 0);
```

このエントリでは、TCP において socket() がどのように呼び出されるかの流れを追ってみる。

なお、押さえておくべき実装に関しては下記がある。

```c
struct socket
socket.ops
struct sock
sock.sk_prot
inet_create
```

## Researched

`__socket()` を追う。

```bash
 ~/kernel/linux
> grep -rn "__sys_socket(" .
./include/linux/socket.h:448:extern int __sys_socket(int family, int type, int protocol);
./net/compat.c:448:		ret = __sys_socket(a0, a1, a[2]);
./net/socket.c:1701:int __sys_socket(int family, int type, int protocol)
./net/socket.c:1720:	return __sys_socket(family, type, protocol);
./net/socket.c:3104:		err = __sys_socket(a0, a1, a[2]);
./tools/perf/trace/beauty/include/linux/socket.h:448:extern int __sys_socket(int family, int type, int protocol);
```

前後を眺めると、`SYSCALL_DEFINE3()` がおる。

```c
SYSCALL_DEFINE3(socket, int, family, int, type, int, protocol)
{
	return __sys_socket(family, type, protocol);
}
```

本体はこれ

```c
int __sys_socket(int family, int type, int protocol)
{
	struct socket *sock;
	int flags;

	sock = __sys_socket_create(family, type,
				   update_socket_protocol(family, type, protocol));
	if (IS_ERR(sock))
		return PTR_ERR(sock);

	flags = type & ~SOCK_TYPE_MASK;
	if (SOCK_NONBLOCK != O_NONBLOCK && (flags & SOCK_NONBLOCK))
		flags = (flags & ~SOCK_NONBLOCK) | O_NONBLOCK;

	return sock_map_fd(sock, flags & (O_CLOEXEC | O_NONBLOCK));
}
```

なので、今のところ、下記の流れで socket() が呼び出される。

- `SYSCALL_DEFINE3(socket, int, family, int, type, int, protocol)`
  - `int __sys_socket(int family, int type, int protocol)`

`__sys_socket()` でやってることとしては、`__sys_socket_create()` でソケットの fd を作成して、その fd に flag を立てている？？？

軽く `__sys_socket_create()` のコメントと実装を確認しておく。

```bash
 ~/kernel/linux
> grep -rn "sock_map_fd(" .
./net/socket.c:485:static int sock_map_fd(struct socket *sock, int flags)
./net/socket.c:1715:	return sock_map_fd(sock, flags & (O_CLOEXEC | O_NONBLOCK));
```

sock_map_fd() の定義はこれ

```c
static int sock_map_fd(struct socket *sock, int flags)
{
	struct file *newfile;
	int fd = get_unused_fd_flags(flags);
	if (unlikely(fd < 0)) {
		sock_release(sock);
		return fd;
	}

	newfile = sock_alloc_file(sock, flags, NULL);
	if (!IS_ERR(newfile)) {
		fd_install(fd, newfile);
		return fd;
	}

	put_unused_fd(fd);
	return PTR_ERR(newfile);
}
```

-> あ、よく見ると、`sock_map_fd()` は `struct socket` のポインタを受けっている。なので、そもそも `__sys_socket_create()` が返すオブジェクトは fd ではなく、`struct socket` 型である。呼び出し元のフラグを元に `get_unused_fd_flags()` を実行することで fd を生成して、その fd に `struct socket` のオブジェクトを紐づけてると考えるのが自然である。

`struct socket` 型のオブジェクトを fd と紐づける流れはわかったので、下記の処理を追っていく。

```c
	sock = __sys_socket_create(family, type,
				   update_socket_protocol(family, type, protocol));
```

特に、`struct sock` のオブジェクトとは何か / `update_socket_protocol()` / `__sys_socket_create()` の実装を追っていく。

`struct socket` に関する情報は色々出てきそうやけど、とりあえず grep する。

```bash
 ~/kernel/linux
> grep -rn "struct\ssock {" .
./include/net/sock.h:341:struct sock {
./tools/testing/selftests/bpf/bpf_tcp_helpers.h:36:struct sock {
./tools/testing/selftests/bpf/progs/test_tcp_estats.c:74:struct sock {
 ~/kernel/linux
> grep -rn "struct\ssocket {" .
./include/linux/net.h:117:struct socket {
```

-> `struct sock` と `struct socket` って何がちゃうんや ... 

- `struct sock`

```c
/**
  *	struct sock - network layer representation of sockets
...
  */
struct sock {
	/*
	 * Now struct inet_timewait_sock also uses sock_common, so please just
	 * don't add nothing before this first member (__sk_common) --acme
	 */
	struct sock_common	__sk_common;
#define sk_node			__sk_common.skc_node
#define sk_nulls_node		__sk_common.skc_nulls_node
#define sk_refcnt		__sk_common.skc_refcnt
#define sk_tx_queue_mapping	__sk_common.skc_tx_queue_mapping
#ifdef CONFIG_SOCK_RX_QUEUE_MAPPING
#define sk_rx_queue_mapping	__sk_common.skc_rx_queue_mapping
#endif

#define sk_dontcopy_begin	__sk_common.skc_dontcopy_begin
#define sk_dontcopy_end		__sk_common.skc_dontcopy_end
#define sk_hash			__sk_common.skc_hash
#define sk_portpair		__sk_common.skc_portpair
#define sk_num			__sk_common.skc_num
#define sk_dport		__sk_common.skc_dport
#define sk_addrpair		__sk_common.skc_addrpair
#define sk_daddr		__sk_common.skc_daddr
#define sk_rcv_saddr		__sk_common.skc_rcv_saddr
#define sk_family		__sk_common.skc_family
#define sk_state		__sk_common.skc_state
#define sk_reuse		__sk_common.skc_reuse
#define sk_reuseport		__sk_common.skc_reuseport
#define sk_ipv6only		__sk_common.skc_ipv6only
#define sk_net_refcnt		__sk_common.skc_net_refcnt
#define sk_bound_dev_if		__sk_common.skc_bound_dev_if
#define sk_bind_node		__sk_common.skc_bind_node
#define sk_prot			__sk_common.skc_prot
#define sk_net			__sk_common.skc_net
#define sk_v6_daddr		__sk_common.skc_v6_daddr
#define sk_v6_rcv_saddr	__sk_common.skc_v6_rcv_saddr
#define sk_cookie		__sk_common.skc_cookie
#define sk_incoming_cpu		__sk_common.skc_incoming_cpu
#define sk_flags		__sk_common.skc_flags
#define sk_rxhash		__sk_common.skc_rxhash

	/* early demux fields */
	struct dst_entry __rcu	*sk_rx_dst;
	int			sk_rx_dst_ifindex;
	u32			sk_rx_dst_cookie;

	socket_lock_t		sk_lock;
	atomic_t		sk_drops;
	int			sk_rcvlowat;
	struct sk_buff_head	sk_error_queue;
	struct sk_buff_head	sk_receive_queue;
	/*
	 * The backlog queue is special, it is always used with
	 * the per-socket spinlock held and requires low latency
	 * access. Therefore we special case it's implementation.
	 * Note : rmem_alloc is in this structure to fill a hole
	 * on 64bit arches, not because its logically part of
	 * backlog.
	 */
	struct {
		atomic_t	rmem_alloc;
		int		len;
		struct sk_buff	*head;
		struct sk_buff	*tail;
	} sk_backlog;

#define sk_rmem_alloc sk_backlog.rmem_alloc

	int			sk_forward_alloc;
	u32			sk_reserved_mem;
#ifdef CONFIG_NET_RX_BUSY_POLL
	unsigned int		sk_ll_usec;
	/* ===== mostly read cache line ===== */
	unsigned int		sk_napi_id;
#endif
	int			sk_rcvbuf;
	int			sk_disconnects;

	struct sk_filter __rcu	*sk_filter;
	union {
		struct socket_wq __rcu	*sk_wq;
		/* private: */
		struct socket_wq	*sk_wq_raw;
		/* public: */
	};
#ifdef CONFIG_XFRM
	struct xfrm_policy __rcu *sk_policy[2];
#endif

	struct dst_entry __rcu	*sk_dst_cache;
	atomic_t		sk_omem_alloc;
	int			sk_sndbuf;

	/* ===== cache line for TX ===== */
	int			sk_wmem_queued;
	refcount_t		sk_wmem_alloc;
	unsigned long		sk_tsq_flags;
	union {
		struct sk_buff	*sk_send_head;
		struct rb_root	tcp_rtx_queue;
	};
	struct sk_buff_head	sk_write_queue;
	__s32			sk_peek_off;
	int			sk_write_pending;
	__u32			sk_dst_pending_confirm;
	u32			sk_pacing_status; /* see enum sk_pacing */
	long			sk_sndtimeo;
	struct timer_list	sk_timer;
	__u32			sk_priority;
	__u32			sk_mark;
	unsigned long		sk_pacing_rate; /* bytes per second */
	unsigned long		sk_max_pacing_rate;
	struct page_frag	sk_frag;
	netdev_features_t	sk_route_caps;
	int			sk_gso_type;
	unsigned int		sk_gso_max_size;
	gfp_t			sk_allocation;
	__u32			sk_txhash;

	/*
	 * Because of non atomicity rules, all
	 * changes are protected by socket lock.
	 */
	u8			sk_gso_disabled : 1,
				sk_kern_sock : 1,
				sk_no_check_tx : 1,
				sk_no_check_rx : 1,
				sk_userlocks : 4;
	u8			sk_pacing_shift;
	u16			sk_type;
	u16			sk_protocol;
	u16			sk_gso_max_segs;
	unsigned long	        sk_lingertime;
	struct proto		*sk_prot_creator;
	rwlock_t		sk_callback_lock;
	int			sk_err,
				sk_err_soft;
	u32			sk_ack_backlog;
	u32			sk_max_ack_backlog;
	kuid_t			sk_uid;
	u8			sk_txrehash;
#ifdef CONFIG_NET_RX_BUSY_POLL
	u8			sk_prefer_busy_poll;
	u16			sk_busy_poll_budget;
#endif
	spinlock_t		sk_peer_lock;
	int			sk_bind_phc;
	struct pid		*sk_peer_pid;
	const struct cred	*sk_peer_cred;

	long			sk_rcvtimeo;
	ktime_t			sk_stamp;
#if BITS_PER_LONG==32
	seqlock_t		sk_stamp_seq;
#endif
	atomic_t		sk_tskey;
	atomic_t		sk_zckey;
	u32			sk_tsflags;
	u8			sk_shutdown;

	u8			sk_clockid;
	u8			sk_txtime_deadline_mode : 1,
				sk_txtime_report_errors : 1,
				sk_txtime_unused : 6;
	bool			sk_use_task_frag;

	struct socket		*sk_socket;
	void			*sk_user_data;
#ifdef CONFIG_SECURITY
	void			*sk_security;
#endif
	struct sock_cgroup_data	sk_cgrp_data;
	struct mem_cgroup	*sk_memcg;
	void			(*sk_state_change)(struct sock *sk);
	void			(*sk_data_ready)(struct sock *sk);
	void			(*sk_write_space)(struct sock *sk);
	void			(*sk_error_report)(struct sock *sk);
	int			(*sk_backlog_rcv)(struct sock *sk,
						  struct sk_buff *skb);
#ifdef CONFIG_SOCK_VALIDATE_XMIT
	struct sk_buff*		(*sk_validate_xmit_skb)(struct sock *sk,
							struct net_device *dev,
							struct sk_buff *skb);
#endif
	void                    (*sk_destruct)(struct sock *sk);
	struct sock_reuseport __rcu	*sk_reuseport_cb;
#ifdef CONFIG_BPF_SYSCALL
	struct bpf_local_storage __rcu	*sk_bpf_storage;
#endif
	struct rcu_head		sk_rcu;
	netns_tracker		ns_tracker;
};
```

-> ソケット対応するデータや扱うためのメンバーが乗っかってる。

- `struct socket`

```c
/**
 *  struct socket - general BSD socket
 *  @state: socket state (%SS_CONNECTED, etc)
 *  @type: socket type (%SOCK_STREAM, etc)
 *  @flags: socket flags (%SOCK_NOSPACE, etc)
 *  @ops: protocol specific socket operations
 *  @file: File back pointer for gc
 *  @sk: internal networking protocol agnostic socket representation
 *  @wq: wait queue for several uses
 */
struct socket {
	socket_state		state;

	short			type;

	unsigned long		flags;

	struct file		*file;
	struct sock		*sk;
	const struct proto_ops	*ops; /* Might change with IPV6_ADDRFORM or MPTCP. */

	struct socket_wq	wq;
};
```

-> `strcut socket` のメンバの state の TCP の遷移する状態を保持する変数を格納してそう。
-> type には SOCK_STREAM が入ってそう。
-> あ、`struct socket` のメンバに `struct sock` がおった ... 

`struct sock` のメンバには `struct socket` がおる。なんやろなこれ ...

- [ ] `struct socket` のメンバの `const struct proto_ops *ops` には何が入るかが気になるので確認する。
- [ ] `struct socket` の変数が `socket(AF_INET, SOCK_STREAM, 0)` からどのようにして作成されるかを調査する。

先に、`const struct proto_ops *ops` について調べようと思ったけど、`__sys_socket_create()` の実装を確認した方が大枠を確認できるとおもたので、一旦そっちを確認する。

```bash
 ~/kernel/linux
> grep -rn "__sys_socket_create(" .
./net/socket.c:1644:static struct socket *__sys_socket_create(int family, int type, int protocol)
./net/socket.c:1671:	sock = __sys_socket_create(family, type, protocol);
./net/socket.c:1706:	sock = __sys_socket_create(family, type,
```

socket() の定義

> SYNOPSIS
>        #include <sys/types.h>          /* See NOTES */
>        #include <sys/socket.h>
> 
>        int socket(int domain, int type, int protocol);

`__sys_socket_create()` の定義

```c
static struct socket *__sys_socket_create(int family, int type, int protocol)
{
	struct socket *sock;
	int retval;

	/* Check the SOCK_* constants for consistency.  */
	BUILD_BUG_ON(SOCK_CLOEXEC != O_CLOEXEC);
	BUILD_BUG_ON((SOCK_MAX | SOCK_TYPE_MASK) != SOCK_TYPE_MASK);
	BUILD_BUG_ON(SOCK_CLOEXEC & SOCK_TYPE_MASK);
	BUILD_BUG_ON(SOCK_NONBLOCK & SOCK_TYPE_MASK);

	if ((type & ~SOCK_TYPE_MASK) & ~(SOCK_CLOEXEC | SOCK_NONBLOCK))
		return ERR_PTR(-EINVAL);
	type &= SOCK_TYPE_MASK;

    // この実装を追っていく。
	retval = sock_create(family, type, protocol, &sock);
	if (retval < 0)
		return ERR_PTR(retval);

	return sock;
}
```

`sock_create()` の定義の場所を確認する。

```bash
 ~/kernel/linux
> grep -rn "int\ssock_create(" .
./include/linux/net.h:254:int sock_create(int family, int type, int proto, struct socket **res);
./net/socket.c:1620:int sock_create(int family, int type, int protocol, struct socket **res)
```

`sock_create()` の定義

```c
/**
 *	sock_create - creates a socket
 *	@family: protocol family (AF_INET, ...)
 *	@type: communication type (SOCK_STREAM, ...)
 *	@protocol: protocol (0, ...)
 *	@res: new socket
 *
 *	A wrapper around __sock_create().
 *	Returns 0 or an error. This function internally uses GFP_KERNEL.
 */

int sock_create(int family, int type, int protocol, struct socket **res)
{
	return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);
}
```

-> あぁ、`socket()` の引数とおんなじ感じの引数になっている。`current` は CPU で実行中のプロセスを格納するためのグローバル変数やった認識で、`nsproxy` は名前空間を紐づけるメンバやった認識。KubeArmor の開発をしている際に、q2ven に教えてもらった気がする。なので、`current->nsproxy->net_ns` には CPU 上で実行されているプロセスが属している network namespace を指している。

- [The Linux Kernel Data Structure Journey — “struct nsproxy” | by Shlomi Boutnaru, Ph.D. | Medium](https://medium.com/@boutnaru/the-linux-kernel-data-structure-journey-struct-nsproxy-b032c71715c5)

`current` は `struct task_struct` 型であるので、定義箇所を確認する。

```bash
 ~/kernel/linux
> grep -rn "struct\stask_struct\s{" .
...
./include/linux/sched.h:748:struct task_struct {
...
```

定義

```c
struct task_struct {
...
	/* Namespaces: */
	struct nsproxy			*nsproxy;
...
```

```bash
 ~/kernel/linux
> grep -rn "struct\snsproxy\s{" .
./include/linux/nsproxy.h:32:struct nsproxy {
```

```c
/*
 * A structure to contain pointers to all per-process
 * namespaces - fs (mount), uts, network, sysvipc, etc.
 *
 * The pid namespace is an exception -- it's accessed using
 * task_active_pid_ns.  The pid namespace here is the
 * namespace that children will use.
 *
 * 'count' is the number of tasks holding a reference.
 * The count for each namespace, then, will be the number
 * of nsproxies pointing to it, not the number of tasks.
 *
 * The nsproxy is shared by tasks which share all namespaces.
 * As soon as a single namespace is cloned or unshared, the
 * nsproxy is copied.
 */
struct nsproxy {
	refcount_t count;
	struct uts_namespace *uts_ns;
	struct ipc_namespace *ipc_ns;
	struct mnt_namespace *mnt_ns;
	struct pid_namespace *pid_ns_for_children;
	struct net 	     *net_ns;
	struct time_namespace *time_ns;
	struct time_namespace *time_ns_for_children;
	struct cgroup_namespace *cgroup_ns;
};
```

-> `struct nsproxy` には各 namespace が定義されている。

次は、`__sock_create()` の定義が記述されている箇所について調べる。

```bash
 ~/kernel/linux
> grep -rn "int\s__sock_create(" .
./include/linux/net.h:252:int __sock_create(struct net *net, int family, int type, int proto,
./net/socket.c:1500:int __sock_create(struct net *net, int family, int type, int protocol,
```

長いけど、`__socket_create()` の定義はこれ

```c
/**
 *	__sock_create - creates a socket
 *	@net: net namespace
 *	@family: protocol family (AF_INET, ...)
 *	@type: communication type (SOCK_STREAM, ...)
 *	@protocol: protocol (0, ...)
 *	@res: new socket
 *	@kern: boolean for kernel space sockets
 *
 *	Creates a new socket and assigns it to @res, passing through LSM.
 *	Returns 0 or an error. On failure @res is set to %NULL. @kern must
 *	be set to true if the socket resides in kernel space.
 *	This function internally uses GFP_KERNEL.
 */

int __sock_create(struct net *net, int family, int type, int protocol,
			 struct socket **res, int kern)
{
	int err;
	struct socket *sock;
	const struct net_proto_family *pf;

	/*
	 *      Check protocol is in range
	 */
	if (family < 0 || family >= NPROTO)
		return -EAFNOSUPPORT;
	if (type < 0 || type >= SOCK_MAX)
		return -EINVAL;

	/* Compatibility.

	   This uglymoron is moved from INET layer to here to avoid
	   deadlock in module load.
	 */
	if (family == PF_INET && type == SOCK_PACKET) {
		pr_info_once("%s uses obsolete (PF_INET,SOCK_PACKET)\n",
			     current->comm);
		family = PF_PACKET;
	}

	// 後述の security_socket_post_create() との違いがよくわからん。
	err = security_socket_create(family, type, protocol, kern);
	if (err)
		return err;

	/*
	 *	Allocate the socket and allow the family to set things up. if
	 *	the protocol is 0, the family is instructed to select an appropriate
	 *	default.
	 */
	sock = sock_alloc();
	if (!sock) {
		net_warn_ratelimited("socket: no more sockets\n");
		return -ENFILE;	/* Not exactly a match, but its the
				   closest posix thing */
	}

	sock->type = type;

#ifdef CONFIG_MODULES
	/* Attempt to load a protocol module if the find failed.
	 *
	 * 12/09/1996 Marcin: But! this makes REALLY only sense, if the user
	 * requested real, full-featured networking support upon configuration.
	 * Otherwise module support will break!
	 */
	if (rcu_access_pointer(net_families[family]) == NULL)
		request_module("net-pf-%d", family);
#endif

	rcu_read_lock();
	// pf には何が入っているかを調査すると、ソケット作成時処理を終えるようになるはず。
	pf = rcu_dereference(net_families[family]);
	err = -EAFNOSUPPORT;
	if (!pf)
		goto out_release;

	/*
	 * We will call the ->create function, that possibly is in a loadable
	 * module, so we have to bump that loadable module refcnt first.
	 */
	if (!try_module_get(pf->owner))
		goto out_release;

	/* Now protected by module ref count */
	rcu_read_unlock();

	// 重要そう
	err = pf->create(net, sock, protocol, kern);
	if (err < 0)
		goto out_module_put;

	/*
	 * Now to bump the refcnt of the [loadable] module that owns this
	 * socket at sock_release time we decrement its refcnt.
	 */
	if (!try_module_get(sock->ops->owner))
		goto out_module_busy;

	/*
	 * Now that we're done with the ->create function, the [loadable]
	 * module can have its refcnt decremented
	 */
	module_put(pf->owner);
	// 重要そう
	err = security_socket_post_create(sock, family, type, protocol, kern);
	if (err)
		goto out_sock_release;
	*res = sock;

	return 0;

out_module_busy:
	err = -EAFNOSUPPORT;
out_module_put:
	sock->ops = NULL;
	module_put(pf->owner);
out_sock_release:
	sock_release(sock);
	return err;

out_release:
	rcu_read_unlock();
	goto out_sock_release;
}
```

`net_families` に対してプロトコルファミリー毎に処理を設定している箇所が見つからなかった ...
`err = pf->create(net, sock, protocol, kern);` の処理が要な気がするねんけど ...

適当にググると、`net/ipv4/af_inet.c` にプロトコルファミリーに依存したソケットの create 処理の実装があるとの情報を確認したので、確認してみる。

- [linux: socketとNet名前空間 - φ(・・*)ゞ ｳｰﾝ　カーネルとか弄ったりのメモ](https://kernhack.hatenablog.com/entry/2015/09/07/234028)

```bash
 ~/kernel/linux
> grep -rn "\s.create" net/ipv4/af_inet.c
1144:	.create = inet_create,
```

`pf->create()` を呼び出すと、実行される本体はこれ

```c
static const struct net_proto_family inet_family_ops = {
	.family = PF_INET,
	.create = inet_create,
	.owner	= THIS_MODULE,
};
```

-> これが、関数ポインタになってるっぽい。

この構造体は、`inet_init()` の `sock_register()` によって登録されている。
`sock_register()` の実装を追うのは一旦置いておく。

定義の箇所を確認

```bash
 ~/kernel/linux
> grep -rn "\sinet_init(" .
./net/ipv4/af_inet.c:1951:static int __init inet_init(void)
```

定義はこれ

```c
static int __init inet_init(void)
{
...
	/*
	 *	Tell SOCKET that we are alive...
	 */

	(void)sock_register(&inet_family_ops);
...
	/* Register the socket-side information for inet_create. */
	for (r = &inetsw[0]; r < &inetsw[SOCK_MAX]; ++r)
		INIT_LIST_HEAD(r);

	for (q = inetsw_array; q < &inetsw_array[INETSW_ARRAY_LEN]; ++q)
		inet_register_protosw(q);
...
fs_initcall(inet_init);
```

-> カーネルの初期化時に `inet_init()` が呼び出される。そのため、初期化時に `inet_family_ops` のメンバーである `inet_create()` が呼び出されて、socket() を呼び出すための下準備が完了する流れなんかな ...

inet_register_protosw() で登録しているハンドラは下記で定義されている。

```c
/* Upon startup we insert all the elements in inetsw_array[] into
 * the linked list inetsw.
 */
static struct inet_protosw inetsw_array[] =
{
	{
		.type =       SOCK_STREAM,
		.protocol =   IPPROTO_TCP,
		.prot =       &tcp_prot,
		.ops =        &inet_stream_ops,
		.flags =      INET_PROTOSW_PERMANENT |
			      INET_PROTOSW_ICSK,
	},

	{
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_UDP,
		.prot =       &udp_prot,
		.ops =        &inet_dgram_ops,
		.flags =      INET_PROTOSW_PERMANENT,
       },

       {
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_ICMP,
		.prot =       &ping_prot,
		.ops =        &inet_sockraw_ops,
		.flags =      INET_PROTOSW_REUSE,
       },

       {
	       .type =       SOCK_RAW,
	       .protocol =   IPPROTO_IP,	/* wild card */
	       .prot =       &raw_prot,
	       .ops =        &inet_sockraw_ops,
	       .flags =      INET_PROTOSW_REUSE,
       }
};

#define INETSW_ARRAY_LEN ARRAY_SIZE(inetsw_array)
```

-> `SOCK_STREAM` といった、socket() の第二引数で渡される値に関するハンドラが登録されている。

`inet_register_protosw()` の定義箇所を確認する。

```bash
 ~/kernel/linux
> grep -rn "void\sinet_register_protosw(" .
./include/net/protocol.h:104:void inet_register_protosw(struct inet_protosw *p);
./net/ipv4/af_inet.c:1189:void inet_register_protosw(struct inet_protosw *p)
```

定義はこれ

```c
void inet_register_protosw(struct inet_protosw *p)
{
	struct list_head *lh;
	struct inet_protosw *answer;
	int protocol = p->protocol;
	struct list_head *last_perm;

	spin_lock_bh(&inetsw_lock);

	if (p->type >= SOCK_MAX)
		goto out_illegal;

	/* If we are trying to override a permanent protocol, bail. */
	last_perm = &inetsw[p->type];
	list_for_each(lh, &inetsw[p->type]) {
		answer = list_entry(lh, struct inet_protosw, list);
		/* Check only the non-wild match. */
		if ((INET_PROTOSW_PERMANENT & answer->flags) == 0)
			break;
		if (protocol == answer->protocol)
			goto out_permanent;
		last_perm = lh;
	}

	/* Add the new entry after the last permanent entry if any, so that
	 * the new entry does not override a permanent entry when matched with
	 * a wild-card protocol. But it is allowed to override any existing
	 * non-permanent entry.  This means that when we remove this entry, the
	 * system automatically returns to the old behavior.
	 */
	list_add_rcu(&p->list, last_perm);
out:
	spin_unlock_bh(&inetsw_lock);

	return;

out_permanent:
	pr_err("Attempt to override permanent protocol %d\n", protocol);
	goto out;

out_illegal:
	pr_err("Ignoring attempt to register invalid socket type %d\n",
	       p->type);
	goto out;
}
EXPORT_SYMBOL(inet_register_protosw);
```

-> `inet_init()` 内の `inet_register_protosw()` で `inetsw` に `inetsw_array` の要素を登録して行っている。

これまでは、`inet_create()` の登録処理を追ってみたが、次は、`pf->create()` で呼び出される実体である `inet_create()` の処理を追っていく。

定義の箇所はこれ

```bash
 ~/kernel/linux
> grep -rn "int\sinet_create(" .
./net/ipv4/af_inet.c:251:static int inet_create(struct net *net, struct socket *sock, int protocol,
```

定義はこれ

```c
/*
 *	Create an inet socket.
 */

static int inet_create(struct net *net, struct socket *sock, int protocol,
		       int kern)
...
	list_for_each_entry_rcu(answer, &inetsw[sock->type], list) {

		err = 0;
		/* Check the non-wild match. */
		if (protocol == answer->protocol) {
			if (protocol != IPPROTO_IP)
				break;
		} else {
			/* Check for the two wild cases. */
			if (IPPROTO_IP == protocol) {
				protocol = answer->protocol;
				break;
			}
			if (IPPROTO_IP == answer->protocol)
				break;
		}
		err = -EPROTONOSUPPORT;
	}
...
```

-> 内部では sock->state に SS_UNCONNECTED を代入したりしているが、struct socket *sock のセットアップをしていっている。また、`init_inet()` で初期化されたオブジェクトから socket() の引数に応じて `sock->ops` に ops の関数ポインタを設定している。

```c
static struct inet_protosw inetsw_array[] =
{
	{
		.type =       SOCK_STREAM,
		.protocol =   IPPROTO_TCP,
		.prot =       &tcp_prot,
		.ops =        &inet_stream_ops,
		.flags =      INET_PROTOSW_PERMANENT |
			      INET_PROTOSW_ICSK,
	},
```

今回は `SOCK_STREAM` を socket() に引き渡した時の処理を追っていきたいので、`inet_stream_ops()` の実装を追う。

```bash
> grep -rn "inet_stream_ops" .
grep: ./arch/x86/boot/compressed/vmlinux.bin: binary file matches
./include/net/inet_common.h:11:extern const struct proto_ops inet_stream_ops;
./net/ipv4/af_inet.c:1051:const struct proto_ops inet_stream_ops = {
./net/ipv4/af_inet.c:1083:EXPORT_SYMBOL(inet_stream_ops);
./net/ipv4/af_inet.c:1157:		.ops =        &inet_stream_ops,
grep: ./net/ipv4/af_inet.o: binary file matches
./net/ipv6/ipv6_sockglue.c:625:				WRITE_ONCE(sk->sk_socket->ops, &inet_stream_ops);
grep: ./net/ipv6/ipv6_sockglue.o: binary file matches
./net/mptcp/protocol.c:65:	return &inet_stream_ops;
./net/xfrm/espintcp.c:586:	build_protos(&espintcp_prot, &espintcp_ops, &tcp_prot, &inet_stream_ops);
...
```

-> あぁ、ops って構造体なんね ... ってことは、sock->ops->accept(...) みたいな感じで登録されたシステムコールが内部で呼び出される感じなんや。

ちなみに、accept() の呼び出しは下の感じやった。

```bash
 ~/kernel/linux
> grep -rn "sock->ops->accept" .
./fs/ocfs2/cluster/tcp.c:1805:	ret = sock->ops->accept(sock, new_sock, O_NONBLOCK, false);
./net/rds/tcp_listen.c:122:	ret = sock->ops->accept(sock, new_sock, O_NONBLOCK, true);
```

一応、`struct inet_protosw` の型を調べて `ops` の型を調べる。

```bash
 ~/kernel/linux
> grep -rn "struct\sinet_protosw\s{" .
./include/net/protocol.h:76:struct inet_protosw {
```

```c
/* This is used to register socket interfaces for IP protocols.  */
struct inet_protosw {
	struct list_head list;

        /* These two fields form the lookup key.  */
	unsigned short	 type;	   /* This is the 2nd argument to socket(2). */
	unsigned short	 protocol; /* This is the L4 protocol number.  */

	struct proto	 *prot;
	const struct proto_ops *ops;
  
	unsigned char	 flags;      /* See INET_PROTOSW_* below.  */
};
```

-> ops って `struct proto_ops` 型の構造体やったんか ...

```bash
 ~/kernel/linux
> grep -rn "struct\sproto_ops\s{" .
./include/linux/net.h:161:struct proto_ops {
```

```c
struct proto_ops {
	int		family;
	struct module	*owner;
	int		(*release)   (struct socket *sock);
	int		(*bind)	     (struct socket *sock,
				      struct sockaddr *myaddr,
				      int sockaddr_len);
	int		(*connect)   (struct socket *sock,
				      struct sockaddr *vaddr,
				      int sockaddr_len, int flags);
	int		(*socketpair)(struct socket *sock1,
				      struct socket *sock2);
	int		(*accept)    (struct socket *sock,
				      struct socket *newsock, int flags, bool kern);
	int		(*getname)   (struct socket *sock,
				      struct sockaddr *addr,
				      int peer);
	__poll_t	(*poll)	     (struct file *file, struct socket *sock,
				      struct poll_table_struct *wait);
	int		(*ioctl)     (struct socket *sock, unsigned int cmd,
				      unsigned long arg);
#ifdef CONFIG_COMPAT
	int	 	(*compat_ioctl) (struct socket *sock, unsigned int cmd,
				      unsigned long arg);
#endif
	int		(*gettstamp) (struct socket *sock, void __user *userstamp,
				      bool timeval, bool time32);
	int		(*listen)    (struct socket *sock, int len);
	int		(*shutdown)  (struct socket *sock, int flags);
	int		(*setsockopt)(struct socket *sock, int level,
				      int optname, sockptr_t optval,
				      unsigned int optlen);
	int		(*getsockopt)(struct socket *sock, int level,
				      int optname, char __user *optval, int __user *optlen);
	void		(*show_fdinfo)(struct seq_file *m, struct socket *sock);
	int		(*sendmsg)   (struct socket *sock, struct msghdr *m,
				      size_t total_len);
	/* Notes for implementing recvmsg:
	 * ===============================
	 * msg->msg_namelen should get updated by the recvmsg handlers
	 * iff msg_name != NULL. It is by default 0 to prevent
	 * returning uninitialized memory to user space.  The recvfrom
	 * handlers can assume that msg.msg_name is either NULL or has
	 * a minimum size of sizeof(struct sockaddr_storage).
	 */
	int		(*recvmsg)   (struct socket *sock, struct msghdr *m,
				      size_t total_len, int flags);
	int		(*mmap)	     (struct file *file, struct socket *sock,
				      struct vm_area_struct * vma);
	ssize_t 	(*splice_read)(struct socket *sock,  loff_t *ppos,
				       struct pipe_inode_info *pipe, size_t len, unsigned int flags);
	void		(*splice_eof)(struct socket *sock);
	int		(*set_peek_off)(struct sock *sk, int val);
	int		(*peek_len)(struct socket *sock);

	/* The following functions are called internally by kernel with
	 * sock lock already held.
	 */
	int		(*read_sock)(struct sock *sk, read_descriptor_t *desc,
				     sk_read_actor_t recv_actor);
	/* This is different from read_sock(), it reads an entire skb at a time. */
	int		(*read_skb)(struct sock *sk, skb_read_actor_t recv_actor);
	int		(*sendmsg_locked)(struct sock *sk, struct msghdr *msg,
					  size_t size);
	int		(*set_rcvlowat)(struct sock *sk, int val);
};
```

-> ほえー、こんな感じになってるんか、ops の配下に知ってるシステムコールとかが生えている！これで、ipv4 とか ipv6 とか気にせず呼び出せるように抽象化されてる感じなんね。

話を戻して、`inet_stream_ops` の構造体に関して調査する。

定義はこれ

```c
const struct proto_ops inet_stream_ops = {
	.family		   = PF_INET,
	.owner		   = THIS_MODULE,
	.release	   = inet_release,
	.bind		   = inet_bind,
	.connect	   = inet_stream_connect,
	.socketpair	   = sock_no_socketpair,
	.accept		   = inet_accept,
	.getname	   = inet_getname,
	.poll		   = tcp_poll,
	.ioctl		   = inet_ioctl,
	.gettstamp	   = sock_gettstamp,
	.listen		   = inet_listen,
	.shutdown	   = inet_shutdown,
	.setsockopt	   = sock_common_setsockopt,
	.getsockopt	   = sock_common_getsockopt,
	.sendmsg	   = inet_sendmsg,
	.recvmsg	   = inet_recvmsg,
#ifdef CONFIG_MMU
	.mmap		   = tcp_mmap,
#endif
	.splice_eof	   = inet_splice_eof,
	.splice_read	   = tcp_splice_read,
	.read_sock	   = tcp_read_sock,
	.read_skb	   = tcp_read_skb,
	.sendmsg_locked    = tcp_sendmsg_locked,
	.peek_len	   = tcp_peek_len,
#ifdef CONFIG_COMPAT
	.compat_ioctl	   = inet_compat_ioctl,
#endif
	.set_rcvlowat	   = tcp_set_rcvlowat,
};
EXPORT_SYMBOL(inet_stream_ops);
```

-> 各メンバーは別途 `inet_` の prefix がついて定義されているようです。

socket() の作成のフローを追って行ったが、一旦 socket() が返す fd を使用して呼び出すことができるシステムコールの実装を確認することにする。

どのシステムコールでも良かったが、`bind()` の実装を追うことにする。(難しかったら、他のシステムコールにする。)

`bind()` の実体は `inet_bind()` なので、その定義を追う。

---

`sruct sock_common` には各プロトコルに共通する処理が魔と待ている感じはするが、後述の `#define sk_node` とかの処理の意味がイマイチわからんかった。

```c
struct sock {
	/*
	 * Now struct inet_timewait_sock also uses sock_common, so please just
	 * don't add nothing before this first member (__sk_common) --acme
	 */
	struct sock_common	__sk_common;
#define sk_node			__sk_common.skc_node
...
```

## 結論

...

## 参考

...
