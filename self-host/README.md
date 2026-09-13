**English** | [简体中文](README-ZH_CN.md)

# Self-host your own relay (coturn)

MyDesk works out of the box on our public relay servers. If you'd rather keep your
session traffic on infrastructure **you** control — for privacy, compliance, or
because your usage is heavy — you can run your own relay. It takes one command, and
your data never passes through us.

This is the same mechanism our own relay nodes use (`use-auth-secret` with a static
key), just hosted by you.

---

## Requirements

- A Linux server (VPS) with a **public IP** — Ubuntu / Debian / CentOS all fine
- Root access
- Docker (the script installs it if it's missing)
- Open these ports (in both the OS firewall **and** your cloud provider's security group):
  - `3478/udp` and `3478/tcp` — TURN/STUN
  - `5349/tcp` and `5349/udp` — TURN over TLS/DTLS
  - `49152-65535/udp` — relay media ports

> The relay feature in the app requires a paid plan (the relay entitlement / VIP).

---

## One-command deploy

Copy `deploy-coturn.sh` to your server and run it as root:

```bash
scp deploy-coturn.sh root@YOUR_SERVER:/root/
ssh root@YOUR_SERVER 'bash /root/deploy-coturn.sh'
```

Or, once you host the file somewhere:

```bash
curl -fsSL https://your.domain/deploy-coturn.sh | sudo bash
```

The script will: install Docker if needed → detect the public IP → generate a
random **static key** → create a self-signed TLS certificate → write
`/opt/mydesk-coturn/turnserver.conf` → start the `coturn` container → open firewall
ports (ufw) → **print the values to paste into MyDesk**.

Useful flags:

```bash
--ip 1.2.3.4            # force the public IP (if auto-detect is wrong)
--dir /opt/mydesk-coturn
--turn-port 3478 --tls-port 5349
```

---

## What it prints, and where it goes

The script ends with a block like this. Map it to the **Custom relay** dialog in
the app (Settings → Custom relay / 自定义中继 → Add config):

| Value printed            | Field in MyDesk            | Example                          |
|--------------------------|----------------------------|----------------------------------|
| Name                     | 名称 Name                  | `My relay`                       |
| TURN server              | TURN 服务器                | `turn:203.0.113.7:3478`          |
| STUN server              | STUN 服务器                | `stun:203.0.113.7:3478`          |
| Static secret            | 静态密钥 (鉴权方式=静态密钥)| `9f2c…` (the printed key)        |
| Bandwidth                | 服务器带宽 (Kb/s)          | `102400` for a 100 Mbps uplink   |

> **Auth method: pick "Static secret" (静态密钥).** This deployment runs coturn in
> `use-auth-secret` mode, so the static key is what authenticates the session. Do
> **not** use the Username/Password option with this config.

After saving: turn the config on for **控制时 / 被控时** as needed, then flip the
switch for the device in **My Devices**. Connections on the enabled side will now
relay through your own server.

---

## Verify

```bash
# container is up and coturn is listening
docker logs -f mydesk-coturn
```

Then start a remote session with the relay enabled. If it connects, you're done.
If it doesn't, check the log line for `401` (auth) or dropped relay ports
(see Troubleshooting).

---

## Manage it

```bash
# logs
docker logs -f mydesk-coturn

# rotate the static key (then re-paste it in the app)
rm /opt/mydesk-coturn/turnserver.conf && sudo bash deploy-coturn.sh

# upgrade the container
docker rm -f mydesk-coturn && sudo bash deploy-coturn.sh

# uninstall
docker rm -f mydesk-coturn && rm -rf /opt/mydesk-coturn
```

---

## Troubleshooting

- **Connects but falls back to the public relay** — the config isn't enabled for
  this side. Check the 控制时 / 被控时 toggles and the device switch.
- **Auth fails (`401` in the log)** — make sure the app is set to **静态密钥** and
  the key matches exactly (re-paste from the script output).
- **Reaches the server but no media** — open `49152-65535/udp` in your cloud
  provider's **security group** (VPS firewalls often block this range).
- **Only works on some networks** — use the `turns:` (TLS) address on port 5349;
  many corporate networks block plain UDP/TCP but allow TLS.
- **CentOS / RHEL with SELinux** — add `:Z` to the volume mounts in the script, e.g.
  `-v "$DIR/turnserver.conf:/etc/coturn/turnserver.conf:ro,Z"`.
- **Behind NAT (private IP on the NIC)** — pass `--ip <your.public.ip>` so coturn
  advertises the right address.

---

*Bring your own relay — your sessions, your infrastructure.*
