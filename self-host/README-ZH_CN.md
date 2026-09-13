[English](README.md) | **简体中文**

# 自建中继（coturn）

MyDesk 默认使用我们的公共中继服务器，开箱即用。如果你希望会话流量走**你自己**
的基础设施——出于隐私、合规，或者因为你用量很大——你可以自建一台中继服务器。
一条命令即可完成，数据不经过我们。

这和我们自己的中继节点用的是同一套机制（`use-auth-secret` + 静态密钥），只是由你来部署。

---

## 前提条件

- 一台带**公网 IP** 的 Linux 服务器（VPS）——Ubuntu / Debian / CentOS 均可
- root 权限
- Docker（未安装时脚本会自动装）
- 放行以下端口（**系统防火墙和云服务商安全组都要开**）：
  - `3478/udp` 和 `3478/tcp` —— TURN/STUN
  - `5349/tcp` 和 `5349/udp` —— TURN over TLS/DTLS
  - `49152-65535/udp` —— 中继媒体端口

> App 里的中继功能需要付费档位（中继权限 / VIP）。

---

## 一条命令部署

把 `deploy-coturn.sh` 传到服务器，用 root 运行：

```bash
scp deploy-coturn.sh root@你的服务器:/root/
ssh root@你的服务器 'bash /root/deploy-coturn.sh'
```

或者，等你把脚本托管到某个地址之后：

```bash
curl -fsSL https://your.domain/deploy-coturn.sh | sudo bash
```

脚本会：缺 Docker 就装 → 探测公网 IP → 生成随机**静态密钥** → 生成自签名 TLS 证书 →
写 `/opt/mydesk-coturn/turnserver.conf` → 启动 `coturn` 容器 → 放行防火墙端口（ufw）→
**把要填进 MyDesk 的值打印出来**。

常用参数：

```bash
--ip 1.2.3.4            # 强制指定公网 IP（自动探测不准时用）
--dir /opt/mydesk-coturn
--turn-port 3478 --tls-port 5349
```

---

## 打印出来的值，填到哪里

脚本最后会输出这样一段。对照 App 里的**自定义中继**弹窗
（设置 → 自定义中继 → 新增配置）填写：

| 打印的值        | MyDesk 里的字段             | 示例                             |
|-----------------|-----------------------------|----------------------------------|
| 名称 Name       | 名称                        | `My relay`                       |
| TURN server     | TURN 服务器                 | `turn:203.0.113.7:3478`          |
| STUN server     | STUN 服务器                 | `stun:203.0.113.7:3478`          |
| 静态密钥        | 静态密钥（鉴权方式=静态密钥）| `9f2c…`（脚本打印的那串）        |
| 带宽            | 服务器带宽 (Kb/s)           | 100 Mbps 上行填 `102400`         |

> **鉴权方式请选「静态密钥」。** 这套部署让 coturn 跑在 `use-auth-secret` 模式，
> 由静态密钥完成鉴权。**不要**对它用「用户名/密码」选项。

保存后：按需为**控制时 / 被控时**启用该配置，再到**我的设备**里打开对应设备的开关。
启用侧之后的连接就会走你自己的服务器。

---

## 验证

```bash
# 容器在跑、coturn 在监听
docker logs -f mydesk-coturn
```

然后打开中继发起一次远控会话。连上即可。若连不上，看日志里有没有 `401`（鉴权失败）
或媒体端口被丢（见「排障」）。

---

## 日常管理

```bash
# 看日志
docker logs -f mydesk-coturn

# 轮换静态密钥（之后要在 App 里重新粘贴）
rm /opt/mydesk-coturn/turnserver.conf && sudo bash deploy-coturn.sh

# 升级容器
docker rm -f mydesk-coturn && sudo bash deploy-coturn.sh

# 卸载
docker rm -f mydesk-coturn && rm -rf /opt/mydesk-coturn
```

---

## 排障

- **连上了但走了公共中继** —— 该配置没在这一侧启用。检查 控制时 / 被控时 开关和设备开关。
- **鉴权失败（日志出现 `401`）** —— 确认 App 里选的是**静态密钥**，且密钥完全一致
  （从脚本输出重新粘贴）。
- **能到服务器但没有画面** —— 在云服务商**安全组**里放行 `49152-65535/udp`
  （VPS 防火墙常拦这段）。
- **只在部分网络能用** —— 改用 5349 的 `turns:`（TLS）地址；很多公司网络会封普通
  UDP/TCP，但放行 TLS。
- **CentOS / RHEL 开了 SELinux** —— 给脚本里的挂载加 `:Z`，例如
  `-v "$DIR/turnserver.conf:/etc/coturn/turnserver.conf:ro,Z"`。
- **NAT 后面（网卡是内网 IP）** —— 传 `--ip <你的公网IP>`，让 coturn 上报正确地址。

---

*自带中继——你的会话，你的基础设施。*
