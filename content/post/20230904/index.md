---
draft: false
title: "How to use KubeArmor to enforce security on containerized workloads"
date: 2023-09-04T23:51:48+09:00
tags: ["KubeArmor", "Container", "Linux"]
pinned: true
ogimage: "img/images/20230904.png"
---

## Overview

<!-- KubeArmor を systemd mode で動作させる際、K8s でオーケストレーションされていないコンテナにおけるセキュリティの強制を実施することができます。 -->

When running KubeArmor in `systemd mode`, it is possible to enforce security on containers that are not orchestrated with K8s.

- [Support Matrix - KubeArmor](https://docs.kubearmor.io/kubearmor/quick-links/support_matrix)

> Containerized: Workloads that are containerized but not k8s orchestrated are supported. KubeArmor installed in  can be used to protect such workloads.

<!-- このエントリでは systemd mode で動作させた KubeArmor で作成したセキュリティの強制を使用して特定のコンテナで実行できるコマンドの制御を実施します。

具体的には、このエントリでは下記のポリシーをカスタマイズし、特定のコンテナ内で diff コマンドを実行できないセキュリティポリシーの作成と適用を実施します。 -->

This entry uses security enforcement created by KubeArmor running in `systemd mode` to control which commands can be executed in specific containers.

Specifically, I will customize the following policy to create and apply a security policy that prevents **the diff command** from being executed in a particular container.

- [KubeArmor/examples/kubearmor_containerpolicy.yaml](https://github.com/kubearmor/KubeArmor/blob/main/examples/kubearmor_containerpolicy.yaml)

```yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: process-block
spec:
  severity: 5
  message: "a critical file was accessed"
  tags:
  - WARNING
  selector:
    matchLabels:
      kubearmor.io/container.name: lb
  process:
    matchPaths:
      - path: /usr/bin/ls
      - path: /usr/bin/sleep
  action:
    Block
```

<!-- なお、下記の wiki にコンテナライズされたワークロードにおけるセキュリティの強制に関する記述があるので、併せてご参照ください。 -->

Please also refer to the wiki below for a description of security enforcement for containerized workloads.

- [KubeArmor to protect IoT Edge containerized workloads](https://github.com/kubearmor/KubeArmor/wiki/KubeArmor-to-protect-IoT-Edge-containerized-workloads)

## Steps

Development environment (Ubuntu 20.04 on EC2)

```bash
ubuntu ~
> uname -r
5.15.0-1040-aws
```

<!-- コンテナ内で diff コマンドを実行できないように矯正するポリシーを作成 -->

Create a policy that prevents **the diff command** from being executed in containers

```bash
ubuntu ~
> cat container.yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: block-diff
spec:
  selector:
    matchLabels:
      kubearmor.io/container.name: container
  process:
    matchPaths:
      - path: /usr/bin/diff
  action:
    Block
```

<!-- このポリシー karmor client を使用して適用 -->

Apply this policy using the karmor client

```
ubuntu ~
> karmor vm policy add container.yaml
Success
```

<!-- そうすると、ポリシーの内容に基づいた AppArmor のプロファイルが作成されます。プロファイル名は、KubeArmor の場合は `kubearmor_` の prefix の後に、ポリシーで `kubearmor.io/container.name` に指定した文字列を連結した文字列となります。 -->

This will create an AppArmor profile based on the contents of the policy. The profile name is a string consisting of the prefix `kubearmor_` for KubeArmor followed by the string specified in `kubearmor.io/container.name` in the policy.

```bash
ubuntu ~
> ls /etc/apparmor.d/kubearmor_*
/etc/apparmor.d/kubearmor_container
```

<!-- AppArmor のプロファイルとは別に KubeArmor のポリシーが作成されていることも確認できます。 -->

You can also see that the KubeArmor policy is created separately from the AppArmor profile.

```bash
ubuntu ~
> sudo ls /opt/kubearmor/policies/
block-diff.yaml
```

<!-- こうして作成した AppArmor のプロファイルを docker run の `--security-opt` に引き渡してコンテナを起動します。このコンテナ内で diff コマンドを実行すると `Permission denied` となることから、KubeArmor のよるセキュリティの強制が正常に適用されていることが確認できました。 -->

The created AppArmor profile is passed to docker run `--security-opt` to start the container. Running **the diff command** in this container will show `Permission denied`, confirming that the security enforcement by KubeArmor has been successfully applied 🎉🎉🎉

```bash
ubuntu ~
> docker run --rm --security-opt apparmor=kubearmor_container -it ubuntu bash
root@0383459dd77c:/# diff -h
bash: /usr/bin/diff: Permission denied
```

<!-- なお、docker run コマンドにおける `--security-opt` の詳細は下記に記述があります。 -->

The details of `--security-opt` in docker run command are described below.

- [Docker run reference | Docker Docs](https://docs.docker.com/engine/reference/run/#security-configuration)

> --security-opt="apparmor=PROFILE"	Set the apparmor profile to be applied to the container

## Reference

- [KubeArmor to protect IoT Edge containerized workloads](https://github.com/kubearmor/KubeArmor/wiki/KubeArmor-to-protect-IoT-Edge-containerized-workloads)
- [KubeArmor/examples/kubearmor_containerpolicy.yaml](https://github.com/kubearmor/KubeArmor/blob/main/examples/kubearmor_containerpolicy.yaml)
