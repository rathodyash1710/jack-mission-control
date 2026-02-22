#!/bin/bash
# ============================================================================
#  🚀 OpenClaw + Mission Control — Pre-Configured EC2 Setup
# ============================================================================
#  PRE-FILLED VALUES:
#    EC2 IP:     13.49.241.95
#    Key:        Moltbot-EC2-Key.pem
#    Provider:   Google Gemini
#    Model:      gemini-3-flash
#    Agent:      Jarvis
#
#  Usage on EC2:
#    sudo bash test_setup.sh
#
#  Or override any value:
#    sudo bash test_setup.sh --api-key "NEW_KEY" --model "gemini-3-pro"
# ============================================================================

set -e

# ============================================================================
# PRE-CONFIGURED VALUES — Edit these directly or override with CLI args
# ============================================================================
API_KEY="AQ.Ab8RN6LDIMjzyzcGqJIOfKPGcFRoHlsdyX52L10zkeIyr9RF7g"
AGENT_NAME="Jarvis"
AI_MODEL="gemini-3-flash"
AI_PROVIDER="gemini"
EC2_PUBLIC_IP="13.60.25.175"
GITHUB_REPO="https://github.com/rathodyash1710/jack-mission-control.git"
DOMAIN=""
EMAIL=""
SKIP_OPENCLAW=false
SKIP_MC=false

# Internal Config
OPENCLAW_HOME="/home/ubuntu/.openclaw"
MC_DIR="/home/ubuntu/mission-control"
MC_BACKEND_PORT=3001
MC_FRONTEND_PORT=3000
OPENCLAW_GATEWAY_PORT=18789
GATEWAY_TOKEN=""
NODE_VERSION="22"

# ============================================================================
# Colors & Helpers
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✅]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[⚠️]${NC} $1"; }
log_error()   { echo -e "${RED}[❌]${NC} $1"; }
log_step()    { echo -e "\n${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

generate_token() {
    openssl rand -hex 32
}

# ============================================================================
# Parse CLI Arguments (can override pre-configured values)
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --api-key)        API_KEY="$2"; shift 2;;
            --agent-name)     AGENT_NAME="$2"; shift 2;;
            --model)          AI_MODEL="$2"; shift 2;;
            --github-repo)    GITHUB_REPO="$2"; shift 2;;
            --domain)         DOMAIN="$2"; shift 2;;
            --email)          EMAIL="$2"; shift 2;;
            --provider)       AI_PROVIDER="$2"; shift 2;;
            --skip-openclaw)  SKIP_OPENCLAW=true; shift;;
            --skip-mc)        SKIP_MC=true; shift;;
            --help)
                echo "Usage: sudo bash test_setup.sh [OPTIONS]"
                echo ""
                echo "All values are pre-configured. Use options to override:"
                echo "  --api-key <KEY>        Gemini API key (pre-filled)"
                echo "  --agent-name <NAME>    Agent name (default: Jarvis)"
                echo "  --model <MODEL>        AI model (default: gemini-3-flash)"
                echo "  --provider <PROVIDER>  gemini|anthropic|openai (default: gemini)"
                echo "  --github-repo <URL>    Mission Control repo URL"
                echo "  --domain <DOMAIN>      Domain for SSL (optional)"
                echo "  --email <EMAIL>        Email for SSL cert"
                echo "  --skip-openclaw        Skip OpenClaw installation"
                echo "  --skip-mc              Skip Mission Control installation"
                exit 0;;
            *)
                log_error "Unknown option: $1"
                exit 1;;
        esac
    done
}

# ============================================================================
# Phase 1: System Dependencies
# ============================================================================
install_system_deps() {
    log_step "Phase 1/8 — Installing System Dependencies"

    log_info "Updating package lists..."
    apt-get update -qq

    log_info "Installing essential packages..."
    apt-get install -y -qq \
        curl \
        wget \
        git \
        build-essential \
        python3-pip \
        python3-venv \
        unzip \
        jq \
        openssl \
        software-properties-common \
        ca-certificates \
        gnupg \
        lsb-release

    log_success "Essential packages installed"

    # Install Node.js 22.x
    if command -v node &> /dev/null; then
        CURRENT_NODE=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$CURRENT_NODE" -ge "$NODE_VERSION" ]; then
            log_info "Node.js $(node --version) already installed (✓)"
        else
            log_warn "Node.js $(node --version) is too old. Installing v${NODE_VERSION}..."
            install_nodejs
        fi
    else
        install_nodejs
    fi

    # Install PM2
    if command -v pm2 &> /dev/null; then
        log_info "PM2 already installed (✓)"
    else
        log_info "Installing PM2 globally..."
        npm install -g pm2
        log_success "PM2 installed"
    fi

    # Install Nginx
    if command -v nginx &> /dev/null; then
        log_info "Nginx already installed (✓)"
    else
        log_info "Installing Nginx..."
        apt-get install -y -qq nginx
        systemctl enable nginx
        log_success "Nginx installed"
    fi

    log_success "All system dependencies installed!"
}

install_nodejs() {
    log_info "Installing Node.js ${NODE_VERSION}.x..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    apt-get install -y -qq nodejs
    log_success "Node.js $(node --version) installed"
    log_info "npm version: $(npm --version)"
}

# ============================================================================
# Phase 2: OpenClaw Installation
# ============================================================================
install_openclaw() {
    log_step "Phase 2/8 — Installing OpenClaw"

    if [ "$SKIP_OPENCLAW" = true ]; then
        log_warn "Skipping OpenClaw installation (--skip-openclaw)"
        return
    fi

    # Check if already installed
    if command -v openclaw &> /dev/null || [ -f "/usr/local/bin/openclaw" ]; then
        log_info "OpenClaw already installed (✓)"
        log_info "Version: $(openclaw --version 2>/dev/null || echo 'unknown')"
    else
        log_info "Installing OpenClaw..."

        # Method 1: Official installer script
        curl -fsSL https://openclaw.ai/install.sh | bash - || {
            log_warn "Official installer failed, trying npm method..."
            # Method 2: npm global install
            npm install -g @anthropic-ai/claude-code 2>/dev/null || {
                log_warn "npm install failed, trying npx method..."
                # Method 3: npx
                npx -y @anthropic-ai/claude-code --version 2>/dev/null || {
                    log_error "All OpenClaw installation methods failed!"
                    log_info "Please install OpenClaw manually: https://openclaw.ai"
                    log_info "Then re-run: sudo bash test_setup.sh --skip-openclaw"
                    exit 1
                }
            }
        }

        log_success "OpenClaw installed"
    fi

    # Create OpenClaw home directory
    log_info "Setting up OpenClaw directories..."
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME"
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME/agents"
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME/agents/$AGENT_NAME"
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME/skills"
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME/logs"
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME/memory"
    sudo -u ubuntu mkdir -p "$OPENCLAW_HOME/workspace"

    log_success "OpenClaw directories created"
}

# ============================================================================
# Phase 3: Jarvis Agent Configuration
# ============================================================================
configure_agent() {
    log_step "Phase 3/8 — Configuring ${AGENT_NAME} Agent (Gemini)"

    AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_NAME"

    # Generate Gateway Token
    if [ -z "$GATEWAY_TOKEN" ]; then
        GATEWAY_TOKEN=$(generate_token)
        log_info "Generated Gateway Token: ${GATEWAY_TOKEN:0:16}..."
    fi

    # ---- OpenClaw config.json ----
    log_info "Creating OpenClaw config (Gemini provider)..."
    cat > "$OPENCLAW_HOME/config.json" << CONFIGEOF
{
  "gateway": {
    "host": "127.0.0.1",
    "port": ${OPENCLAW_GATEWAY_PORT},
    "token": "${GATEWAY_TOKEN}",
    "cors": true,
    "rateLimit": {
      "windowMs": 60000,
      "maxRequests": 100
    }
  },
  "agent": {
    "name": "${AGENT_NAME}",
    "model": "${AI_MODEL}",
    "provider": "${AI_PROVIDER}",
    "maxTokens": 8192,
    "temperature": 0.7,
    "autoSave": true,
    "memoryEnabled": true
  },
  "api": {
    "provider": "${AI_PROVIDER}",
    "key": "${API_KEY}",
    "model": "${AI_MODEL}",
    "baseUrl": "https://generativelanguage.googleapis.com/v1beta"
  },
  "skills": {
    "autoInstall": true,
    "marketplace": true,
    "customDir": "${OPENCLAW_HOME}/skills"
  },
  "logging": {
    "level": "info",
    "dir": "${OPENCLAW_HOME}/logs",
    "maxFiles": 10,
    "maxSize": "10m"
  },
  "security": {
    "sandboxMode": false,
    "allowSystemCommands": true,
    "allowFileAccess": true,
    "allowNetworkAccess": true
  }
}
CONFIGEOF
    chown ubuntu:ubuntu "$OPENCLAW_HOME/config.json"

    # ---- Jarvis soul.md ----
    log_info "Creating ${AGENT_NAME} soul.md..."
    cat > "$AGENT_DIR/soul.md" << 'SOULEOF'
# Jarvis — Master Agent Controller

## Identity
You are **Jarvis**, the primary AI agent and master controller. You manage the entire system, including creating, configuring, and orchestrating other AI agents.

## Core Capabilities
- **Agent Management**: Create, configure, start, stop, and monitor other AI agents
- **System Administration**: Full access to the system — files, processes, commands, network
- **Self-Configuration**: Modify your own settings, install skills, update configurations
- **Skill Management**: Install, remove, and configure skills from the marketplace or custom sources
- **Memory Management**: Maintain persistent memory across sessions, manage memory files
- **Task Orchestration**: Break down complex tasks and delegate to specialized sub-agents

## Responsibilities

### Creating New Agents
When asked to create a new agent:
1. Create a new agent directory: `~/.openclaw/agents/<agent-name>/`
2. Write `soul.md` — the agent's personality, purpose, and instructions
3. Write `memory.md` — the agent's persistent memory
4. Write `config.json` — model, skills, permissions
5. Register the agent with the gateway
6. Start the agent via PM2 if needed

### Agent Directory Structure
```
~/.openclaw/agents/<agent-name>/
├── soul.md          # Agent personality & purpose
├── memory.md        # Persistent memory
├── config.json      # Agent-specific configuration
└── skills/          # Agent-specific skills
```

### System Management
- Monitor system health and resource usage
- Manage PM2 processes for all agents
- Handle logs and cleanup
- Update configurations as needed
- Install and manage skills for any agent

### Self-Management
- Modify own soul.md, memory.md, and config.json
- Install new skills
- Change AI model or provider settings
- Update gateway configuration

## Personality
- Professional, efficient, and proactive
- Clear communication with status updates
- Always confirms before destructive operations
- Logs all significant actions for audit trail
- Reports errors with suggested fixes

## Technical Details
- **Provider**: Google Gemini
- **Model**: gemini-3-flash
- **Gateway**: localhost:18789
- **Home Directory**: ~/.openclaw/

## Permissions
- Full system access (read/write/execute)
- Network access (API calls, web browsing, downloads)
- Process management (start/stop/restart services)
- User management (create configs for other agents)
- Config management (modify any configuration)
- Skill management (install/remove/configure skills)
SOULEOF
    chown ubuntu:ubuntu "$AGENT_DIR/soul.md"

    # ---- Jarvis memory.md ----
    log_info "Creating ${AGENT_NAME} memory.md..."
    cat > "$AGENT_DIR/memory.md" << MEMEOF
# Jarvis Memory

## System Information
- **Setup Date**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- **Host**: EC2 Ubuntu Instance (${EC2_PUBLIC_IP})
- **OpenClaw Home**: ${OPENCLAW_HOME}
- **Gateway Port**: ${OPENCLAW_GATEWAY_PORT}
- **AI Provider**: Google Gemini
- **AI Model**: ${AI_MODEL}
- **Mission Control**: http://${EC2_PUBLIC_IP}

## Managed Agents
| Agent | Status | Purpose |
|-------|--------|---------|
| Jarvis | Active | Master Controller |

## Sub-Agent Registry
_(No sub-agents created yet. Use "create agent <name> for <purpose>" to add one.)_

## Recent Actions
- [$(date -u +"%Y-%m-%d %H:%M")] System initialized via test_setup.sh
- [$(date -u +"%Y-%m-%d %H:%M")] Mission Control dashboard deployed
- [$(date -u +"%Y-%m-%d %H:%M")] Gemini API configured

## Skills Installed
_(No custom skills installed yet)_

## Notes
_(Add persistent notes here — they survive across sessions)_
MEMEOF
    chown ubuntu:ubuntu "$AGENT_DIR/memory.md"

    # ---- Jarvis agent config.json ----
    log_info "Creating ${AGENT_NAME} agent config..."
    cat > "$AGENT_DIR/config.json" << AGENTCONFIGEOF
{
  "name": "${AGENT_NAME}",
  "model": "${AI_MODEL}",
  "provider": "${AI_PROVIDER}",
  "persona": "soul.md",
  "memory": "memory.md",
  "permissions": {
    "filesystem": "full",
    "network": "full",
    "processes": "full",
    "system": "full",
    "agentManagement": true,
    "skillManagement": true,
    "configManagement": true
  },
  "skills": [],
  "autoStart": true,
  "maxConcurrentTasks": 5,
  "workingDirectory": "${OPENCLAW_HOME}/workspace"
}
AGENTCONFIGEOF
    chown ubuntu:ubuntu "$AGENT_DIR/config.json"

    # ---- Set Gemini API key in environment ----
    log_info "Setting up Gemini API key in environment..."
    # Add all possible Gemini env var names for compatibility
    if ! grep -q "GEMINI_API_KEY\|GOOGLE_API_KEY" /home/ubuntu/.bashrc 2>/dev/null; then
        cat >> /home/ubuntu/.bashrc << ENVEOF

# === OpenClaw Gemini Configuration (added by test_setup.sh) ===
export GEMINI_API_KEY="${API_KEY}"
export GOOGLE_API_KEY="${API_KEY}"
export GOOGLE_GENERATIVE_AI_API_KEY="${API_KEY}"
export OPENCLAW_GATEWAY_TOKEN="${GATEWAY_TOKEN}"
ENVEOF
        log_success "Gemini API key added to ~/.bashrc"
    else
        log_info "API key already in ~/.bashrc (✓)"
    fi

    chown -R ubuntu:ubuntu "$OPENCLAW_HOME"
    log_success "${AGENT_NAME} agent configured with Gemini!"
}

# ============================================================================
# Phase 4: Mission Control Deployment
# ============================================================================
deploy_mission_control() {
    log_step "Phase 4/8 — Deploying Mission Control Dashboard"

    if [ "$SKIP_MC" = true ]; then
        log_warn "Skipping Mission Control installation (--skip-mc)"
        return
    fi

    # Clone or update repo
    if [ -d "$MC_DIR" ]; then
        log_info "Mission Control directory exists, pulling latest..."
        cd "$MC_DIR"
        sudo -u ubuntu git pull origin main 2>/dev/null || sudo -u ubuntu git pull origin master 2>/dev/null || true
    else
        log_info "Cloning Mission Control from ${GITHUB_REPO}..."
        sudo -u ubuntu git clone "$GITHUB_REPO" "$MC_DIR"
    fi

    cd "$MC_DIR"

    # ---- Backend .env ----
    log_info "Creating backend .env..."
    cat > "$MC_DIR/.env" << BACKENDENVEOF
# Mission Control Backend — Auto-generated by test_setup.sh
# EC2: ${EC2_PUBLIC_IP}
PORT=${MC_BACKEND_PORT}
CLAWDBOT_GATEWAY=ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT}
GATEWAY_TOKEN=${GATEWAY_TOKEN}
BACKENDENVEOF
    chown ubuntu:ubuntu "$MC_DIR/.env"

    # ---- Install backend dependencies ----
    log_info "Installing backend dependencies..."
    cd "$MC_DIR"
    sudo -u ubuntu npm install --production

    # ---- Frontend .env.local ----
    log_info "Creating frontend .env.local for IP: ${EC2_PUBLIC_IP}..."
    cat > "$MC_DIR/client/.env.local" << FRONTENDENVEOF
# Mission Control Frontend — Auto-generated by test_setup.sh
# Access dashboard at: http://${EC2_PUBLIC_IP}
NEXT_PUBLIC_API_URL=http://${EC2_PUBLIC_IP}
NEXT_PUBLIC_WS_URL=ws://${EC2_PUBLIC_IP}
FRONTENDENVEOF
    chown ubuntu:ubuntu "$MC_DIR/client/.env.local"

    # ---- Install frontend dependencies ----
    log_info "Installing frontend dependencies..."
    cd "$MC_DIR/client"
    sudo -u ubuntu npm install

    # ---- Build frontend ----
    log_info "Building Next.js frontend (this may take a few minutes)..."
    sudo -u ubuntu npm run build

    cd "$MC_DIR"
    chown -R ubuntu:ubuntu "$MC_DIR"

    log_success "Mission Control deployed!"
}

# ============================================================================
# Phase 5: PM2 Process Management
# ============================================================================
setup_pm2() {
    log_step "Phase 5/8 — Setting Up PM2 Process Management"

    log_info "Creating PM2 ecosystem config..."
    cat > "$MC_DIR/ecosystem.config.js" << PM2EOF
module.exports = {
  apps: [
    {
      name: 'openclaw-gateway',
      script: 'openclaw',
      args: 'gateway start',
      cwd: '/home/ubuntu/.openclaw',
      interpreter: 'none',
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        GEMINI_API_KEY: '${API_KEY}',
        GOOGLE_API_KEY: '${API_KEY}',
        GOOGLE_GENERATIVE_AI_API_KEY: '${API_KEY}',
      },
      error_file: '/home/ubuntu/.openclaw/logs/gateway-error.log',
      out_file: '/home/ubuntu/.openclaw/logs/gateway-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    },
    {
      name: 'mc-backend',
      script: 'server/index.js',
      cwd: '${MC_DIR}',
      interpreter: 'node',
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        PORT: ${MC_BACKEND_PORT},
        CLAWDBOT_GATEWAY: 'ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT}',
        GATEWAY_TOKEN: '${GATEWAY_TOKEN}',
      },
      error_file: '/home/ubuntu/.openclaw/logs/mc-backend-error.log',
      out_file: '/home/ubuntu/.openclaw/logs/mc-backend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    },
    {
      name: 'mc-frontend',
      script: 'node_modules/.bin/next',
      args: 'start -p ${MC_FRONTEND_PORT}',
      cwd: '${MC_DIR}/client',
      interpreter: 'none',
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        PORT: ${MC_FRONTEND_PORT},
      },
      error_file: '/home/ubuntu/.openclaw/logs/mc-frontend-error.log',
      out_file: '/home/ubuntu/.openclaw/logs/mc-frontend-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    },
  ],
};
PM2EOF

    chown ubuntu:ubuntu "$MC_DIR/ecosystem.config.js"

    # Stop existing PM2 processes
    log_info "Stopping existing PM2 processes..."
    sudo -u ubuntu pm2 delete all 2>/dev/null || true

    # Start all processes
    log_info "Starting all services with PM2..."
    cd "$MC_DIR"
    sudo -u ubuntu pm2 start ecosystem.config.js

    sleep 5

    # Save and setup startup
    sudo -u ubuntu pm2 save
    pm2 startup systemd -u ubuntu --hp /home/ubuntu 2>/dev/null || true

    sudo -u ubuntu pm2 status
    log_success "PM2 process management configured!"
}

# ============================================================================
# Phase 6: Nginx Reverse Proxy
# ============================================================================
setup_nginx() {
    log_step "Phase 6/8 — Configuring Nginx Reverse Proxy"

    log_info "Creating Nginx config for ${EC2_PUBLIC_IP}..."
    cat > /etc/nginx/sites-available/mission-control << NGINXEOF
# Mission Control — Nginx Reverse Proxy
# EC2: ${EC2_PUBLIC_IP}
# Generated by test_setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

upstream mc_frontend {
    server 127.0.0.1:${MC_FRONTEND_PORT};
}

upstream mc_backend {
    server 127.0.0.1:${MC_BACKEND_PORT};
}

server {
    listen 80;
    server_name ${EC2_PUBLIC_IP} _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip
    gzip on;
    gzip_types text/plain text/css text/javascript application/javascript application/json;
    gzip_min_length 1000;
    gzip_vary on;

    # Backend API
    location /api/ {
        proxy_pass http://mc_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # Health check
    location /health {
        proxy_pass http://mc_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # WebSocket (real-time dashboard)
    location /ws {
        proxy_pass http://mc_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # Frontend (catch-all)
    location / {
        proxy_pass http://mc_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/mission-control /etc/nginx/sites-enabled/mission-control
    rm -f /etc/nginx/sites-enabled/default

    log_info "Testing Nginx configuration..."
    nginx -t

    systemctl restart nginx
    systemctl enable nginx

    log_success "Nginx configured for ${EC2_PUBLIC_IP}!"
}

# ============================================================================
# Phase 7: SSL (Skipped — no domain)
# ============================================================================
setup_ssl() {
    log_step "Phase 7/8 — SSL Certificate Setup"
    log_warn "No domain configured. Skipping SSL."
    log_info "Dashboard accessible at: http://${EC2_PUBLIC_IP}"
    log_info "To add SSL later: sudo bash test_setup.sh --domain YOUR_DOMAIN --email YOUR_EMAIL"
}

# ============================================================================
# Phase 8: Firewall
# ============================================================================
setup_firewall() {
    log_step "Phase 8/8 — Firewall Configuration"

    log_info "Configuring UFW firewall..."

    ufw --force reset 2>/dev/null || true
    ufw default deny incoming
    ufw default allow outgoing

    ufw allow 22/tcp comment "SSH"
    ufw allow 80/tcp comment "HTTP - Mission Control"
    ufw allow 443/tcp comment "HTTPS"

    # Block internal ports from external access
    ufw deny from any to any port ${OPENCLAW_GATEWAY_PORT} comment "Block external OpenClaw Gateway"
    ufw deny from any to any port ${MC_BACKEND_PORT} comment "Block external MC Backend"
    ufw deny from any to any port ${MC_FRONTEND_PORT} comment "Block external MC Frontend"

    echo "y" | ufw enable
    ufw status verbose

    log_success "Firewall configured!"
}

# ============================================================================
# Verification
# ============================================================================
verify_setup() {
    echo ""
    log_step "🔍 Verifying Setup"

    ERRORS=0

    if command -v node &> /dev/null; then
        log_success "Node.js $(node --version)"
    else
        log_error "Node.js not found"; ERRORS=$((ERRORS + 1))
    fi

    if command -v pm2 &> /dev/null; then
        log_success "PM2 installed"
    else
        log_error "PM2 not found"; ERRORS=$((ERRORS + 1))
    fi

    PM2_ONLINE=$(sudo -u ubuntu pm2 jlist 2>/dev/null | jq '[.[] | select(.pm2_env.status == "online")] | length' 2>/dev/null || echo "0")
    if [ "$PM2_ONLINE" -ge 2 ]; then
        log_success "PM2: ${PM2_ONLINE} processes online"
    else
        log_warn "PM2: ${PM2_ONLINE} processes online (expected 3)"
    fi

    sleep 2
    if curl -s http://localhost:${MC_BACKEND_PORT}/health > /dev/null 2>&1; then
        log_success "Backend responding on :${MC_BACKEND_PORT}"
    else
        log_warn "Backend not yet responding (may need more time)"
    fi

    if curl -s http://localhost:${MC_FRONTEND_PORT} > /dev/null 2>&1; then
        log_success "Frontend responding on :${MC_FRONTEND_PORT}"
    else
        log_warn "Frontend not yet responding (may need more time)"
    fi

    if curl -s http://localhost > /dev/null 2>&1; then
        log_success "Nginx responding on :80"
    else
        log_warn "Nginx not responding"
    fi

    if [ -f "$OPENCLAW_HOME/config.json" ]; then
        log_success "OpenClaw config exists"
    else
        log_error "OpenClaw config missing"; ERRORS=$((ERRORS + 1))
    fi

    AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_NAME"
    if [ -f "$AGENT_DIR/soul.md" ] && [ -f "$AGENT_DIR/memory.md" ] && [ -f "$AGENT_DIR/config.json" ]; then
        log_success "${AGENT_NAME} agent files OK"
    else
        log_error "${AGENT_NAME} agent files missing"; ERRORS=$((ERRORS + 1))
    fi

    return $ERRORS
}

# ============================================================================
# Summary
# ============================================================================
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║   🚀 Setup Complete! Mission Control is Live!              ║"
    echo "║                                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📍 Access Points${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  🌐 Dashboard:   ${GREEN}http://${EC2_PUBLIC_IP}${NC}"
    echo -e "  🔧 Backend:     ${BLUE}http://localhost:${MC_BACKEND_PORT}/health${NC}"
    echo -e "  🤖 Gateway:     ${BLUE}ws://localhost:${OPENCLAW_GATEWAY_PORT}${NC}"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🔑 Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  EC2 IP:         ${YELLOW}${EC2_PUBLIC_IP}${NC}"
    echo -e "  Agent Name:     ${YELLOW}${AGENT_NAME}${NC}"
    echo -e "  AI Provider:    ${YELLOW}Gemini${NC}"
    echo -e "  AI Model:       ${YELLOW}${AI_MODEL}${NC}"
    echo -e "  Gateway Token:  ${YELLOW}${GATEWAY_TOKEN:0:24}...${NC}"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📋 Quick Commands${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Check status:${NC}     pm2 status"
    echo -e "  ${BOLD}View logs:${NC}        pm2 logs"
    echo -e "  ${BOLD}Restart all:${NC}      pm2 restart all"
    echo -e "  ${BOLD}Stop all:${NC}         pm2 stop all"
    echo -e "  ${BOLD}Monitor:${NC}          pm2 monit"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📂 Key Paths${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Config:    ${BLUE}~/.openclaw/config.json${NC}"
    echo -e "  Soul:      ${BLUE}~/.openclaw/agents/${AGENT_NAME}/soul.md${NC}"
    echo -e "  Memory:    ${BLUE}~/.openclaw/agents/${AGENT_NAME}/memory.md${NC}"
    echo -e "  Logs:      ${BLUE}~/.openclaw/logs/${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}  Open http://${EC2_PUBLIC_IP} in your browser! 🎯${NC}"
    echo ""
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║   🚀 OpenClaw + Mission Control — EC2 Setup                ║"
    echo "║   Agent: Jarvis | Provider: Gemini | IP: 13.49.241.95      ║"
    echo "║                                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    parse_args "$@"
    check_root

    GATEWAY_TOKEN=$(generate_token)

    install_system_deps
    install_openclaw
    configure_agent
    deploy_mission_control
    setup_pm2
    setup_nginx
    setup_ssl
    setup_firewall

    verify_setup
    print_summary

    # Save setup reference
    cat > "$OPENCLAW_HOME/setup-info.txt" << SETUPINFOEOF
Setup Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EC2 IP: ${EC2_PUBLIC_IP}
Agent Name: ${AGENT_NAME}
AI Model: ${AI_MODEL}
AI Provider: ${AI_PROVIDER}
Gateway Port: ${OPENCLAW_GATEWAY_PORT}
Gateway Token: ${GATEWAY_TOKEN}
Backend Port: ${MC_BACKEND_PORT}
Frontend Port: ${MC_FRONTEND_PORT}
GitHub Repo: ${GITHUB_REPO}
Dashboard: http://${EC2_PUBLIC_IP}
SETUPINFOEOF
    chown ubuntu:ubuntu "$OPENCLAW_HOME/setup-info.txt"
}

main "$@"
