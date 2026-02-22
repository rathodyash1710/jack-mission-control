# 🚀 Deployment Guide — OpenClaw + Mission Control on EC2

Complete guide to deploy Jarvis (OpenClaw AI Agent) with Mission Control dashboard on an AWS EC2 Ubuntu instance.

---

## Prerequisites

### 1. Launch EC2 Instance

| Setting | Value |
|---------|-------|
| **AMI** | Ubuntu 22.04 or 24.04 LTS |
| **Instance Type** | `t3.medium` (min) or `t3.large` (recommended) |
| **Storage** | 30GB gp3 SSD |
| **Key Pair** | Create or select a `.pem` key pair |

### 2. Security Group Rules

| Port | Type | Source | Description |
|------|------|--------|-------------|
| 22 | SSH | My IP | SSH access |
| 80 | HTTP | 0.0.0.0/0 | Dashboard |
| 443 | HTTPS | 0.0.0.0/0 | Dashboard (SSL) |

> ⚠️ **Do NOT open port 18789** — OpenClaw Gateway must stay internal only.

---

## One-Command Setup

### Step 1: SSH into EC2

```bash
ssh -i your-key.pem ubuntu@<YOUR-EC2-PUBLIC-IP>
```

### Step 2: Download & Run Setup Script

```bash
# Clone the repo
git clone https://github.com/Yash-AIML/jack-mission-control.git
cd jack-mission-control

# Run setup (replace YOUR_API_KEY)
sudo bash setup.sh --api-key "YOUR_ANTHROPIC_API_KEY"
```

### Step 3: Open Dashboard

Open in browser: `http://<YOUR-EC2-PUBLIC-IP>`

---

## Setup Script Options

```bash
sudo bash setup.sh \
  --api-key "sk-ant-xxxxx" \          # AI provider API key
  --agent-name "Jarvis" \             # Agent name (default: Jarvis)
  --model "claude-sonnet-4-20250514" \  # AI model
  --provider "anthropic" \            # anthropic or openai
  --domain "ai.example.com" \        # Domain for SSL (optional)
  --email "you@example.com"           # Email for SSL cert
```

| Flag | Default | Description |
|------|---------|-------------|
| `--api-key` | _(prompt)_ | AI API key |
| `--agent-name` | Jarvis | Agent name |
| `--model` | claude-sonnet-4-20250514 | AI model |
| `--provider` | anthropic | anthropic or openai |
| `--domain` | _(none)_ | Domain for SSL |
| `--email` | _(none)_ | Email for SSL |
| `--skip-openclaw` | false | Skip OpenClaw install |
| `--skip-mc` | false | Skip Mission Control |

---

## Post-Setup

### Verify Everything Works

```bash
# Check all services
pm2 status

# Expected output:
# ┌─────────────────────┬──────┬───────┐
# │ Name                │ Mode │ Status│
# ├─────────────────────┼──────┼───────┤
# │ openclaw-gateway    │ fork │ online│
# │ mc-backend          │ fork │ online│
# │ mc-frontend         │ fork │ online│
# └─────────────────────┴──────┴───────┘

# Check logs
pm2 logs

# Test backend health
curl http://localhost:3001/health
```

### Common Commands

```bash
# Restart everything
pm2 restart all

# View real-time logs
pm2 logs --lines 50

# Restart specific service
pm2 restart mc-backend
pm2 restart mc-frontend
pm2 restart openclaw-gateway

# Stop everything
pm2 stop all

# Monitor resources
pm2 monit
```

---

## Configuration Changes

### Change API Key

```bash
nano ~/.openclaw/config.json    # Edit "api.key" field
pm2 restart openclaw-gateway
```

### Change AI Model

```bash
nano ~/.openclaw/config.json    # Edit "agent.model" field
pm2 restart openclaw-gateway
```

### Edit Jarvis Personality

```bash
nano ~/.openclaw/agents/Jarvis/soul.md
```

### Edit Jarvis Memory

```bash
nano ~/.openclaw/agents/Jarvis/memory.md
```

### Update Mission Control Code

```bash
cd ~/mission-control
git pull
cd client && npm run build
pm2 restart mc-frontend mc-backend
```

---

## File Layout on EC2

```
/home/ubuntu/
├── .openclaw/
│   ├── config.json              # OpenClaw main config
│   ├── setup-info.txt           # Setup reference
│   ├── agents/
│   │   └── Jarvis/
│   │       ├── soul.md          # Agent personality
│   │       ├── memory.md        # Persistent memory
│   │       └── config.json      # Agent-specific config
│   ├── skills/                  # Installed skills
│   ├── logs/                    # All log files
│   ├── memory/                  # Memory storage
│   └── workspace/               # Agent working directory
│
├── mission-control/
│   ├── server/index.js          # Backend server
│   ├── client/                  # Next.js frontend
│   ├── .env                     # Backend env vars
│   ├── ecosystem.config.js      # PM2 config
│   └── setup.sh                 # This setup script
│
└── .bashrc                      # Contains API key export
```

---

## Troubleshooting

### Dashboard shows "Disconnected"

```bash
# Check if gateway is running
pm2 status openclaw-gateway

# Check backend logs for gateway connection errors
pm2 logs mc-backend --lines 30

# Verify gateway token matches
cat ~/mission-control/.env
cat ~/.openclaw/config.json | jq '.gateway.token'
```

### 502 Bad Gateway in Browser

```bash
# Check if frontend is running
pm2 status mc-frontend

# Check Nginx config
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

### PM2 Processes Keep Crashing

```bash
# Check error logs
pm2 logs --err --lines 50

# Check memory usage
free -h
pm2 monit
```

### Re-run Setup (Safe)

The setup script is idempotent — safe to re-run:

```bash
cd ~/mission-control
sudo bash setup.sh --api-key "YOUR_KEY"
```

---

## Adding SSL Later

If you get a domain name later:

```bash
# Point your domain's DNS A record to your EC2 IP first, then:
cd ~/mission-control
sudo bash setup.sh --domain yourdomain.com --email you@email.com --skip-openclaw --skip-mc
```

---

## Security Notes

- OpenClaw Gateway (`port 18789`) is **localhost-only** — never exposed publicly
- UFW firewall blocks all ports except 22, 80, 443
- Gateway token is auto-generated (64-char hex) — stored in `~/.openclaw/setup-info.txt`
- All traffic between browser and server goes through Nginx
- Consider setting up SSH key-only authentication (disable password login)
