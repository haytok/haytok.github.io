---
draft: false
title: "「12 ステップで作る 組込みOS自作入門」\nを読んでOS を作成してみた"
date: 2022-10-17T16:00:17Z
tags: ["OS", "Kernel", "C"]
pinned: false
ogimage: "img/images/20221018.png"
---

## 概要

[12 ステップで作る 組込み OS 自作入門](https://kozos.jp/books/makeos/) を読んで、マイコン ([Ｈ８／３０６９Ｆネット対応マイコンＬＡＮボード（完成品）](https://akizukidenshi.com/catalog/g/gK-01271/)) のリソースを管理する小さな OS ([marinOS](https://github.com/haytok/marinOS)) を実装してみました。 割り込みベースでスレッドが切り替わる OS で、いわゆるマイクロカーネルのような思想で実装しています。この本を読んで実装したことを通して学んだことなどの感想を簡単に残したいと思います。なお、本記事は個人の見解であり、所属組織を代表するものではありません。

## 感想と勉強になったこと

この書籍をベースに小さな OS を作成することで学べたことなどを以下に示します。

1. 必要に応じて仕様書を読み込むことの大切さ ([H8/3069 F-ZTAT TM ハードウェアマニュアル](http://www.picosystems.net/dl/ds/device/HD64F3069.pdf), [XMODEM](https://ja.wikipedia.org/wiki/XMODEM), [Tool Interface Standard (TIS) Executable and Linking Format (ELF) Specification Version 1.2](https://refspecs.linuxfoundation.org/elf/elf.pdf), etc ...)
2. C 言語 / アセンブリ言語 / スタックの伸長などの低レイヤーの基本
3. リンカスクリプトを使用したコードやメモリ配置の調整方法
4. 標準ライブラリを一切使用せずにフルスクラッチで必要な処理の実装方法
5. デバイスドライバのような機能の実装方法
6. Bootloader の実装方法
7. ファイル転送プロトコル ([XMODEM](https://ja.wikipedia.org/wiki/XMODEM)) の実装方法
8. ELF ファイルを解析し RAM 上の指定した領域へ展開して起動させるための機能の実装方法
9. 割り込み処理の実装方法
10. 複数のスレッドを起動させ、優先度に応じてスレッドをスケジューリングさせる機能の実装方法
11. メモリ管理の機能の実装方法
12. IPC の機能の実装方法
13. ビジーループではなく外部割り込みを捌く処理の実装方法

この書籍自体は割と古めの本なのですが、このような OS (Kernel) の基本的な機能やマイコンプログラミングの基礎を学べたのは貴重な経験でした。個人的には GUI の複雑なレンダリング処理の実装等の必要が無く、外部のライブラリに依存することなく OS (Kernel) の機能の実装に注力することができたので、学生の頃に読んだ [ゼロからの OS 自作入門](https://book.mynavi.jp/ec/products/detail/id=121220) よりは取っ付きやすかったです。また、マイコンのメモリを直接的かつ自由に取り扱うことができたので、メモリ管理に対する苦手意識が減り、メモリモデルに関する関心が芽生えました。なお、[ゼロからの OS 自作入門](https://book.mynavi.jp/ec/products/detail/id=121220) もすごいたくさんのことを学べた本なので、時間があるうちに再度読み直したいと考えています。先にこの本を読んでいれば、また見方が変わったのかなとも思います。

<!-- - C 言語 / アセンブリ言語 / スタックの伸長などの低レイヤーの基本
  - volatile の必要性を再確認
- Bootloader の実装
  - ROM に書き込まれた Bootloader は一番初めに起動するプログラムです。Bootloader がクライアントから送信される OS ファイルを受信し、RAM 側で展開し、処理を OS のエントリーポイントに移す機能を実装しています。
- デバイスドライバのような機能の実装
  - シリアル通信で受信したデータを操作し、送信するような
- シリアル通信で受信したデータを操作し、送信する機能の実装
  - kermit を使用した命令やデータのやりとり
- デバイスドライバのような機能の実装
  - レジスタやメモリの操作によるハードウェアの制御することが可能となり、例えば特定のアドレスを操作すると送受信したデータを書き込み / 読み出しをする機能の実装 (ex. [メモリマップド I/O](https://ja.wikipedia.org/wiki/%E3%83%A1%E3%83%A2%E3%83%AA%E3%83%9E%E3%83%83%E3%83%97%E3%83%89I/O))
  - [MMU](https://ja.wikipedia.org/wiki/%E3%83%A1%E3%83%A2%E3%83%AA%E7%AE%A1%E7%90%86%E3%83%A6%E3%83%8B%E3%83%83%E3%83%88) の無い CPU において malloc(3) のような機能を実現するための関数の実装
- ファイル転送プロトコル ([XMODEM](https://ja.wikipedia.org/wiki/XMODEM)) の実装
  - データ通信のための適切なレジスタの操作手順
- マルチスレッドを起動させることが可能な機能の実装
  - ch01 の環境構築と ch08 のスレッドの機能の実装が一番難しかった。
- IPC の機能の実装
  - 関数の歳入や排他の概念を知ることができた
- MMU は CPU の機能と言って良い気がする ... -->

## 最後に

前半は環境構築と仕様書の読み方が一番大変だったのですが、後半は OS (Kernel) の本格的な機能を実装したのでかなり読み応えがありました。特に、割り込みによって処理が非同期的に飛ぶ辺りやメモリ管理機能の実装には手こずりました。この本を通して自分は低レイヤーではどのようなデータ構造やアルゴリズムを駆使してリソースが管理されているのか (ex. 動的なメモリの割り当てやスレッドのスケジューリングや排他制御など) に気づきました。そのため、これからはこの OS (Kernel) を拡張しつつ、他の OS (Kernel) のリソース管理がどのようなデータ構造やアルゴリズムを用いて管理されているかを調査してみたいと思います。

## 参考

- [12 ステップで作る 組込み OS 自作入門](https://kozos.jp/books/makeos/)

<!-- ## 背景

## 目的

## 方法

## 結果

## 結論-->