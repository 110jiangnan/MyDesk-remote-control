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
- **Pick Ubuntu 22.04 / 24.04 / 26.04 LTS** (Debian 12 / 13 works too).
  **CentOS / RHEL is not supported** — the script detects it and exits with an error.
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
- **OS image**: **Ubuntu 22.04 / 24.04 / 26.04 LTS** (Debian 12 / 13 also works).
  **Do not pick CentOS / RHEL** — the script doesn't support it.
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
curl -fsSL https://raw.githubusercontent.com/110jiangnan/MyDesk-remote-control/master/self-host/deploy-coturn.sh | sudo bash -s -- --ip YOUR_PUBLIC_IP
```

**Server in mainland China (Gitee — faster there):**
```bash
curl -fsSL https://gitee.com/jiangnan-java/MyDesk-remote-control/raw/master/self-host/deploy-coturn.sh | sudo bash -s -- --ip YOUR_PUBLIC_IP
```

Replace `YOUR_PUBLIC_IP` with the IP from step 1.4 (looks like `203.0.113.7`).
**Do not drop the `--ip` argument** — see 3.1 below for why.

The script will: install coturn (from the distro's own package repo — **no Docker**) →
confirm the public IP → generate a random **static key** and a self-signed certificate →
write the config → start coturn and enable it on boot → try to open the OS firewall →
**print the values to paste into MyDesk** (in the final block).

### 3.1 ⚠️ Always pass the public IP explicitly (the easiest way to waste an hour)

**Why auto-detection isn't enough:** what the script detects is the **egress IP as seen from
outside**, and that is not necessarily the **public IP your devices connect in to**. Three
common cases where the two disagree:

- **The server is behind NAT** — the console shows a public IP, but the machine's own NIC only
  has a **private** address (`10.x` / `172.16–31.x` / `192.168.x`);
- **Multiple NICs / several public IPs** — detection can pick the wrong one;
- **Carrier CGNAT, or traffic leaving and arriving via different egress points** — the egress
  IP and the console's public IP are simply not the same address.

All three end the same way: coturn **advertises a wrong address**, `turn:` won't connect, and
**there's no obvious error** — so you keep blaming the firewall or the client and burn an
afternoon on it.

The rule is simple: **trust the public IP shown in your provider's console** and pass it with
`--ip` rather than leaving it to auto-detection.

**After it finishes, check the block it printed:**

```
  TURN server : turn:203.0.113.7:3478
  STUN server : stun:203.0.113.7:3478
```

That IP **must be your public IP**. If it starts with `10.` / `172.` / `192.168.`, the script
picked up a private address — **re-run with `--ip <your.public.ip>`** and use the newly printed
values in the app.

### 3.2 When running the script by hand, give it execute permission

A script you copied from a browser, or copied from Windows onto the server, has **no execute
permission**. Running `sudo ./deploy-coturn.sh` then fails with:

```
sudo: cannot execute './deploy-coturn.sh': Permission denied (os error 13)
```

This is **not about sudo rights** — the kernel refuses to execute a file that has *no* execute
bit set **even for root**. Two ways around it:

```bash
# Option 1 — set the execute bit, then run it directly
chmod +x deploy-coturn.sh
sudo ./deploy-coturn.sh --ip YOUR_PUBLIC_IP

# Option 2 — leave the bit alone and let bash read the file (simplest)
sudo bash deploy-coturn.sh --ip YOUR_PUBLIC_IP
```

> **Don't edit this script in a Windows editor and copy it over.** Windows writes CRLF line
> endings, and the script then fails with cryptic errors like
> `set: pipefail: invalid option name`. Edit it on the server with `nano deploy-coturn.sh`
> instead.

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
| TLS port         | TLS 端口（可选）            | `5349` (leave blank if unused)   |
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
# coturn log, Ctrl+C to quit (run on the server)
journalctl -u coturn -f

# service status — you want "active (running)"
systemctl status coturn --no-pager
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
journalctl -u coturn -f

# restart / stop / status
systemctl restart coturn
systemctl stop coturn

# upgrade coturn (tracks the distro's package repo)
sudo apt-get update && sudo apt-get install --only-upgrade coturn

# rotate the static key (then re-paste it in the app)
rm /etc/coturn/mydesk-secret && sudo ./deploy-coturn.sh --ip YOUR_PUBLIC_IP

# re-running is safe — the public IP, key and certificate are all reused,
# so a config you already pasted into the app keeps working
sudo ./deploy-coturn.sh --ip YOUR_PUBLIC_IP

# uninstall
sudo apt-get purge -y coturn && sudo rm -rf /etc/coturn /etc/turnserver.conf
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
- **Only works on some networks** — fill the **TLS port** field with the port the
  script prints (5349); many corporate networks block plain UDP/TCP but allow TLS.
  The app then falls back to `turns:` on its own when both UDP and TCP are blocked.
- **Changed IP / rotated the key without syncing** — re-paste the new values into the app.
- **The printed TURN server is a private IP** (starts with `10.` / `172.` / `192.168.`) —
  the server is behind NAT and detection picked the wrong address. Re-run with
  `--ip <your.public.ip>` (see 3.1).
- **`Permission denied (os error 13)`** — the script has no execute permission. Run
  `chmod +x deploy-coturn.sh`, or use `sudo bash deploy-coturn.sh` (see 3.2). Correct sudo
  rights don't help here.
- **Cryptic errors like `set: pipefail: invalid option name`** — the script was saved with
  Windows CRLF line endings. Download it again on the server, or run
  `sudo sed -i 's/\r$//' deploy-coturn.sh`.
- **`apt-get update` hangs or fails** — the box is pointed at an upstream mirror that's slow
  or blocked. Switch `/etc/apt` to `mirrors.aliyun.com` or `mirrors.tuna.tsinghua.edu.cn`
  and re-run.
- **coturn won't start** — on failure the script prints `systemctl cat coturn` plus the last
  20 log lines; paste that and the cause is usually obvious (often a port already in use).
- **CentOS / RHEL** — not supported; use Ubuntu / Debian.

---

*Bring your own relay — your sessions, your infrastructure.*
