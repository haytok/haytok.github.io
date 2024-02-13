---
draft: false
title: "Linux Kernel Code Reading ..."
date: 2024-02-14T01:16:33+09:00
tags: ["Linux"]
pinned: true
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

## 結論

...

## 参考

...
