**English** | [简体中文](README-ZH_CN.md)

# Self-host your own relay (coturn) — step-by-step

MyDesk works out of the box on our public relay servers. If you'd rather keep your
session traffic on infrastructure **you** control — for privacy, compliance, or
because your usage is heavy — you can run your own relay. **One command**, and your
data never passes through us.

> This guide assumes you've **never touched a server before**. Follow it step by
> step; everything is spelled out. All you need is a cloud server and ~15 minutes.

---

## The 1-minute version

- You buy a **cloud server** (a.k.a. VPS / cloud instance) — a computer that runs in
  a data center 24/7 and relays the picture between your two devices.
- **Pick Ubuntu 22.04 / 24.04** — this guide and the script are written for it, and
  it's the least hassle.
- Rough cost: **$5–$10 / month** overseas, **¥30–¥100 / month** in mainland China.

---

## Step 1 — Buy a cloud server

### 1.1 Pick a region first (important)

| Where your devices are | Where to buy |
|---|---|
| Both in **mainland China** | Buy in **mainland China** (lowest latency) |
| Both **overseas** | Buy the closest node — **Hong Kong / Singapore / Japan / US** |
| One China, one overseas | A relay can't fix a cross-ocean hop — buy near each side, or just use the default public relay |

### 1.2 Where to buy

**Overseas (recommended for non-China users):**

| Provider | Notes |
|---|---|
| **Vultr** | Hourly billing, many regions, fast to set up — great first choice |
| **DigitalOcean** | Friendliest UI, $6/mo, excellent docs |
| **Linode (Akamai)** | Long-established, stable |
| **Hetzner** | Cheap and generous (mostly EU/US) |
| **AWS Lightsail** | Amazon's simplified VPS |
| **Oracle Cloud** | Has an **always-free** tier (if you can get one) |

> Overseas providers usually take **credit card / PayPal**.

**Mainland China (recommended for China users):**

| Provider | Look for | Notes |
|---|---|---|
| Alibaba Cloud (阿里云) | "轻量应用服务器" (Lightweight App Server) | Most common, beginner-friendly |
| Tencent Cloud (腾讯云) | "轻量应用服务器" | Often great value |
| Huawei Cloud | "云耀 / 轻量" | |
| JD Cloud / UCloud / Baidu Cloud | "轻量 / 云服务器" | Alternatives |

> China providers require **real-name verification** (ID) and take Alipay/WeChat Pay.
> **Running a relay does not need an ICP filing** (that's only for serving websites
> on ports 80/443, which this doesn't use).

### 1.3 What specs to pick

- **CPU / RAM**: **1 core / 1 GB** is plenty (coturn is light).
- **Bandwidth / traffic**: **this is the key one.** A relay forwards video, so don't
  go too small:
  - If billed by **bandwidth**: pick **≥ 5 Mbps** (more = smoother).
  - If billed by **traffic**: pick **≥ 1 TB / month**.
- **OS image**: **Ubuntu 22.04 LTS** or **Ubuntu 24.04 LTS**.
- Everything else (20 GB disk, snapshots, …) — defaults are fine.

### 1.4 After buying, note two things

1. **Public IP** — like `203.0.113.7` (visible on the console home page).
2. **root password** — set at purchase; if you lost it, click **Reset Password** in
   the console.

---

## Step 2 — Connect to the server

Open a terminal on your computer and log in:

**Windows 10/11:**
1. Search **PowerShell** in the Start menu and open it.
2. Type the line below (replace with your IP) and press Enter:
   ```
   ssh root@YOUR_PUBLIC_IP
   ```
3. The first time it asks `Are you sure...?` — type `yes` and Enter.
4. At `password:` enter your root password.
   **Nothing appears while you type the password — that's normal.** Press Enter when done.

**macOS / Linux:**
Open **Terminal** and type `ssh root@YOUR_PUBLIC_IP` — the rest is the same.

When the prompt changes to something like `root@myhost:~#`, you're **logged in**.

---

## Step 3 — Deploy with one command

On the server (in that terminal window), run:

**Overseas server (GitHub):**
```bash
curl -fsSL https://raw.githubusercontent.com/110jiangnan/MyDesk-remote-control/master/self-host/deploy-coturn.sh | sudo bash
```

**Server in mainland China (Gitee — faster there):**
```bash
curl -fsSL https://gitee.com/jiangnan-java/MyDesk-remote-control/raw/master/self-host/deploy-coturn.sh | sudo bash
```

The script will: install Docker (if missing) → detect the public IP → generate a
random **static key** and a self-signed certificate → write the config → start the
coturn container → try to open the OS firewall → **print the values to paste into
MyDesk** (in the final block).

> Want to read the script first? Open either link in a browser, save it as a file,
> then run `sudo bash deploy-coturn.sh`.

---

## Step 4 — Open the ports (⚠️ the step everyone forgets)

A server keeps most ports closed by default. **Opening them in the OS is not
enough — you must also open them in your cloud provider's console**, or the outside
world simply can't reach it.

The script already tries to open the **OS firewall** (ufw). But the cloud console's
**security group / firewall is a separate layer you must open by hand**.

**Where to open them:**

| Provider | Location |
|---|---|
| Vultr | Console → **Firewall** |
| DigitalOcean | Console → **Networking → Firewalls** |
| AWS Lightsail | Instance → **Networking → Firewall** |
| Oracle Cloud | VCN → **Security Lists** |
| Alibaba / Tencent / Huawei / JD Cloud | Console → **Security Group** (安全组) → your instance |

**How:** add an **Inbound rule**, set the source to `0.0.0.0/0` (allow any IP), and
open all of these:

| Protocol | Port | Purpose |
|---|---|---|
| TCP | 3478 | TURN / STUN |
| UDP | 3478 | TURN / STUN |
| TCP | 5349 | TURN over TLS |
| UDP | 5349 | TURN over DTLS |
| UDP | 49152 - 65535 | Relay media ports |

> Some consoles let you enter a port range in one rule — add the rows above
> accordingly. **Don't skip the UDP rows** — miss them and it connects but shows no
> picture.

---

## Step 5 — Paste the printed values into MyDesk

The script ends with a block like this. Put it into the app's **Custom relay**
dialog (Settings → Custom relay / 自定义中继 → Add config):

| Value printed    | Field in MyDesk            | Example                          |
|------------------|----------------------------|----------------------------------|
| Name             | 名称 Name                  | `My relay`                       |
| TURN server      | TURN 服务器                | `turn:203.0.113.7:3478`          |
| STUN server      | STUN 服务器                | `stun:203.0.113.7:3478`          |
| Static secret    | 静态密钥 (鉴权方式=静态密钥)| `9f2c…` (the printed key)        |
| Bandwidth        | 服务器带宽 (Kb/s)          | `102400` for a 100 Mbps uplink   |

> **Auth method: pick "Static secret" (静态密钥).** This deployment runs coturn in
> `use-auth-secret` mode, so the static key does the authentication. Do **not** use
> the Username/Password option with this config.

After saving: turn the config on for **控制时 / 被控时** as needed, then flip the
switch for the device in **My Devices**. Connections on the enabled side now relay
through your own server.

> The relay feature requires a paid plan (relay entitlement / VIP).

---

## Verify

```bash
# container is up and coturn is listening (run on the server)
docker logs -f mydesk-coturn
```

Then enable the relay in the app and start a remote session. If it connects, you're
done. If not, see Troubleshooting.

> ⚠️ **Important: a custom relay is exclusive.** Once enabled, your connection uses
> **only** it — **if it goes down you can't connect, and there is no automatic
> fallback to the public relay.** A lapsed bill, a crashed coturn, a changed IP, a
> key you forgot to update, a security-group edit — any of these becomes "can't
> connect". So:
> - **Do a real remote session once before you rely on it**, and only then keep it on;
> - **Keep the server online** — don't let the bill lapse, don't power it off;
> - If you change the IP / key, update the config in the app too;
> - When it won't connect, **turn the relay switch off in the app first** — that
>   reverts to the public relay and instantly tells you whether the relay is the culprit.
>
> 🛡️ MyDesk **checks your enabled relay every hour** and warns you if it can't be
> reached. You can also turn on **"Auto-disable relay when unreachable"** at the top
> of the Custom relay page, so it disables itself and falls back to the public relay
> automatically.


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
- **Reaches the server but no picture** — almost always **ports not fully opened**:
  go back to Step 4 and confirm the cloud security group allows UDP 3478,
  UDP 5349, and UDP 49152-65535.
- **Only works on some networks** — use the `turns:` (TLS) address on port 5349;
  many corporate networks block plain UDP/TCP but allow TLS.
- **CentOS / RHEL with SELinux** — add `:Z` to the volume mounts in the script, e.g.
  `-v "$DIR/turnserver.conf:/etc/coturn/turnserver.conf:ro,Z"`.
- **Behind NAT (private IP on the NIC)** — pass `--ip <your.public.ip>` so coturn
  advertises the right address.

---

*Bring your own relay — your sessions, your infrastructure.*
