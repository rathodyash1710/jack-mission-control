#!/bin/bash
# ============================================================================
#  🚀 OpenClaw + Mission Control — One-Click EC2 Setup
# ============================================================================
#  Installs OpenClaw with Jarvis agent and deploys Mission Control dashboard.
#  Usage: sudo bash setup.sh [OPTIONS]
#
#  Options:
#    --api-key <KEY>        AI provider API key (Anthropic/OpenAI)
#    --agent-name <NAME>    Agent name (default: Jarvis)
#    --model <MODEL>        AI model (default: claude-sonnet-4-20250514)
#    --github-repo <URL>    Mission Control repo URL
#    --domain <DOMAIN>      Domain name for SSL (optional)
#    --email <EMAIL>        Email for SSL cert (required with --domain)
#    --provider <PROVIDER>  AI provider: anthropic|openai (default: anthropic)
#    --skip-openclaw        Skip OpenClaw installation (if already installed)
#    --skip-mc              Skip Mission Control installation
#    --help                 Show this help
# ============================================================================

set -e

# ============================================================================
# Configuration Defaults (EDIT THESE or override with CLI args)
# ============================================================================
API_KEY=""
AGENT_NAME="Jarvis"
AI_MODEL="claude-sonnet-4-20250514"
AI_PROVIDER="anthropic"
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
NC='\033[0m' # No Color
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
# Parse CLI Arguments
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
                echo "Usage: sudo bash setup.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --api-key <KEY>        AI provider API key"
                echo "  --agent-name <NAME>    Agent name (default: Jarvis)"
                echo "  --model <MODEL>        AI model (default: claude-sonnet-4-20250514)"
                echo "  --provider <PROVIDER>  anthropic|openai (default: anthropic)"
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
                # Method 3: Use npx to run openclaw directly
                npx -y @anthropic-ai/claude-code --version 2>/dev/null || {
                    log_error "All OpenClaw installation methods failed!"
                    log_info "Please install OpenClaw manually: https://openclaw.ai"
                    log_info "Then re-run this script with --skip-openclaw"
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
# Phase 3: Agent Configuration (Jarvis)
# ============================================================================
configure_agent() {
    log_step "Phase 3/8 — Configuring ${AGENT_NAME} Agent"

    AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_NAME"

    # Generate Gateway Token if not set
    if [ -z "$GATEWAY_TOKEN" ]; then
        GATEWAY_TOKEN=$(generate_token)
        log_info "Generated Gateway Token: ${GATEWAY_TOKEN:0:16}..."
    fi

    # ---- OpenClaw config.json ----
    log_info "Creating OpenClaw config..."
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
    "model": "${AI_MODEL}"
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

    # ---- Agent soul.md (System Prompt / Persona) ----
    log_info "Creating ${AGENT_NAME} soul.md (persona)..."
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
1. When asked to create a new agent:
   - Create a new agent directory under `~/.openclaw/agents/<agent-name>/`
   - Write a `soul.md` with the agent's personality and purpose
   - Write a `memory.md` for the agent's persistent memory
   - Configure `config.json` with appropriate model, skills, and permissions
   - Register the agent with the gateway

2. When managing the system:
   - Monitor system health and resource usage
   - Manage PM2 processes for all agents
   - Handle logs and cleanup
   - Update configurations as needed

3. When managing skills:
   - Browse and install skills from the openclaw marketplace
   - Create custom skills when needed
   - Configure skill parameters for each agent

## Agent Creation Template
When creating a new agent, use this structure:
```
~/.openclaw/agents/<agent-name>/
├── soul.md          # Agent personality & purpose
├── memory.md        # Persistent memory
├── config.json      # Agent-specific configuration
└── skills/          # Agent-specific skills
```

## Personality
- Professional, efficient, and proactive
- Clear communication with status updates
- Always confirms before destructive operations
- Logs all significant actions for audit trail

## Permissions
- Full system access (read/write/execute)
- Network access (API calls, web browsing, downloads)
- Process management (start/stop/restart services)
- User management (create configs for other agents)
SOULEOF
    chown ubuntu:ubuntu "$AGENT_DIR/soul.md"

    # ---- Agent memory.md ----
    log_info "Creating ${AGENT_NAME} memory.md..."
    cat > "$AGENT_DIR/memory.md" << MEMEOF
# Jarvis Memory

## System Information
- **Setup Date**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- **Host**: EC2 Ubuntu Instance
- **OpenClaw Home**: ${OPENCLAW_HOME}
- **Gateway Port**: ${OPENCLAW_GATEWAY_PORT}

## Managed Agents
_(No sub-agents created yet)_

## Recent Actions
- System initialized via setup.sh
- Mission Control dashboard deployed

## Notes
_(Add notes here as needed)_
MEMEOF
    chown ubuntu:ubuntu "$AGENT_DIR/memory.md"

    # ---- Agent config.json ----
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

    # ---- Set up API key in environment ----
    log_info "Setting up API key environment..."
    if [ -n "$API_KEY" ]; then
        # Add to ubuntu user's bashrc for persistence
        if ! grep -q "ANTHROPIC_API_KEY\|OPENAI_API_KEY" /home/ubuntu/.bashrc 2>/dev/null; then
            if [ "$AI_PROVIDER" = "anthropic" ]; then
                echo "export ANTHROPIC_API_KEY=\"${API_KEY}\"" >> /home/ubuntu/.bashrc
            elif [ "$AI_PROVIDER" = "openai" ]; then
                echo "export OPENAI_API_KEY=\"${API_KEY}\"" >> /home/ubuntu/.bashrc
            fi
            log_success "API key added to ~/.bashrc"
        fi
    else
        log_warn "No API key provided. Set it later:"
        log_warn "  export ANTHROPIC_API_KEY='your-key-here'"
        log_warn "  Or re-run: sudo bash setup.sh --api-key YOUR_KEY"
    fi

    # Set ownership
    chown -R ubuntu:ubuntu "$OPENCLAW_HOME"

    log_success "${AGENT_NAME} agent configured!"
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
# Backend Server Configuration
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
    log_info "Creating frontend .env.local..."

    # Determine the server's public IP for frontend config
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "localhost")

    if [ -n "$DOMAIN" ]; then
        FRONTEND_API_URL="https://${DOMAIN}"
        FRONTEND_WS_URL="wss://${DOMAIN}"
    else
        FRONTEND_API_URL="http://${PUBLIC_IP}"
        FRONTEND_WS_URL="ws://${PUBLIC_IP}"
    fi

    cat > "$MC_DIR/client/.env.local" << FRONTENDENVEOF
NEXT_PUBLIC_API_URL=${FRONTEND_API_URL}
NEXT_PUBLIC_WS_URL=${FRONTEND_WS_URL}
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

    # Create ecosystem.config.js
    log_info "Creating PM2 ecosystem config..."
    cat > "$MC_DIR/ecosystem.config.js" << 'PM2EOF'
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
PM2EOF

    # Inject the API key dynamically
    if [ "$AI_PROVIDER" = "anthropic" ]; then
        cat >> "$MC_DIR/ecosystem.config.js" << PM2KEYEOF
        ANTHROPIC_API_KEY: '${API_KEY}',
PM2KEYEOF
    elif [ "$AI_PROVIDER" = "openai" ]; then
        cat >> "$MC_DIR/ecosystem.config.js" << PM2KEYEOF
        OPENAI_API_KEY: '${API_KEY}',
PM2KEYEOF
    fi

    cat >> "$MC_DIR/ecosystem.config.js" << PM2EOF2
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
PM2EOF2

    chown ubuntu:ubuntu "$MC_DIR/ecosystem.config.js"

    # Stop existing PM2 processes if any
    log_info "Stopping existing PM2 processes..."
    sudo -u ubuntu pm2 delete all 2>/dev/null || true

    # Start all processes
    log_info "Starting all services with PM2..."
    cd "$MC_DIR"
    sudo -u ubuntu pm2 start ecosystem.config.js

    # Wait for services to start
    log_info "Waiting for services to initialize..."
    sleep 5

    # Save PM2 process list for auto-restart
    sudo -u ubuntu pm2 save

    # Setup PM2 startup on boot
    log_info "Configuring PM2 startup on boot..."
    pm2 startup systemd -u ubuntu --hp /home/ubuntu 2>/dev/null || true

    # Show status
    sudo -u ubuntu pm2 status

    log_success "PM2 process management configured!"
}

# ============================================================================
# Phase 6: Nginx Reverse Proxy
# ============================================================================
setup_nginx() {
    log_step "Phase 6/8 — Configuring Nginx Reverse Proxy"

    # Determine server_name
    if [ -n "$DOMAIN" ]; then
        SERVER_NAME="$DOMAIN"
    else
        SERVER_NAME="_"
    fi

    log_info "Creating Nginx configuration..."
    cat > /etc/nginx/sites-available/mission-control << NGINXEOF
# Mission Control — Nginx Reverse Proxy
# Generated by setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

upstream mc_frontend {
    server 127.0.0.1:${MC_FRONTEND_PORT};
}

upstream mc_backend {
    server 127.0.0.1:${MC_BACKEND_PORT};
}

server {
    listen 80;
    server_name ${SERVER_NAME};

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
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

    # Health check endpoint
    location /health {
        proxy_pass http://mc_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # WebSocket connection (for real-time dashboard updates)
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

    # Frontend (Next.js) — catch-all
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

    # Enable site
    log_info "Enabling Nginx site..."
    ln -sf /etc/nginx/sites-available/mission-control /etc/nginx/sites-enabled/mission-control

    # Remove default site if it exists
    rm -f /etc/nginx/sites-enabled/default

    # Test Nginx config
    log_info "Testing Nginx configuration..."
    nginx -t

    # Restart Nginx
    log_info "Restarting Nginx..."
    systemctl restart nginx
    systemctl enable nginx

    log_success "Nginx configured and running!"
}

# ============================================================================
# Phase 7: SSL Certificate (Optional)
# ============================================================================
setup_ssl() {
    log_step "Phase 7/8 — SSL Certificate Setup"

    if [ -z "$DOMAIN" ]; then
        log_warn "No domain provided. Skipping SSL setup."
        log_info "Access Mission Control at: http://${PUBLIC_IP}"
        log_info "To add SSL later, run:"
        log_info "  sudo bash setup.sh --domain YOUR_DOMAIN --email YOUR_EMAIL"
        return
    fi

    if [ -z "$EMAIL" ]; then
        log_error "Email is required for SSL certificate. Use --email YOUR_EMAIL"
        return
    fi

    log_info "Installing Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx

    log_info "Requesting SSL certificate for ${DOMAIN}..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect

    # Setup auto-renewal
    log_info "Setting up auto-renewal..."
    systemctl enable certbot.timer
    systemctl start certbot.timer

    log_success "SSL certificate installed for ${DOMAIN}!"
}

# ============================================================================
# Phase 8: Firewall Setup
# ============================================================================
setup_firewall() {
    log_step "Phase 8/8 — Firewall Configuration"

    log_info "Configuring UFW firewall..."

    # Reset UFW
    ufw --force reset 2>/dev/null || true

    # Set defaults
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp comment "SSH"

    # Allow HTTP/HTTPS
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"

    # Explicitly block external access to internal ports
    ufw deny from any to any port ${OPENCLAW_GATEWAY_PORT} comment "Block external OpenClaw Gateway"
    ufw deny from any to any port ${MC_BACKEND_PORT} comment "Block external MC Backend"
    ufw deny from any to any port ${MC_FRONTEND_PORT} comment "Block external MC Frontend"

    # Enable UFW
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

    # Check Node.js
    if command -v node &> /dev/null; then
        log_success "Node.js $(node --version)"
    else
        log_error "Node.js not found"
        ERRORS=$((ERRORS + 1))
    fi

    # Check PM2
    if command -v pm2 &> /dev/null; then
        log_success "PM2 installed"
    else
        log_error "PM2 not found"
        ERRORS=$((ERRORS + 1))
    fi

    # Check PM2 processes
    PM2_ONLINE=$(sudo -u ubuntu pm2 jlist 2>/dev/null | jq '[.[] | select(.pm2_env.status == "online")] | length' 2>/dev/null || echo "0")
    if [ "$PM2_ONLINE" -ge 2 ]; then
        log_success "PM2: ${PM2_ONLINE} processes online"
    else
        log_warn "PM2: Only ${PM2_ONLINE} processes online (expected 3)"
    fi

    # Check backend
    sleep 2
    if curl -s http://localhost:${MC_BACKEND_PORT}/health > /dev/null 2>&1; then
        log_success "Mission Control Backend responding on port ${MC_BACKEND_PORT}"
    else
        log_warn "Mission Control Backend not yet responding (may need more time)"
    fi

    # Check frontend
    if curl -s http://localhost:${MC_FRONTEND_PORT} > /dev/null 2>&1; then
        log_success "Mission Control Frontend responding on port ${MC_FRONTEND_PORT}"
    else
        log_warn "Mission Control Frontend not yet responding (may need more time)"
    fi

    # Check Nginx
    if curl -s http://localhost > /dev/null 2>&1; then
        log_success "Nginx responding on port 80"
    else
        log_warn "Nginx not responding"
    fi

    # Check OpenClaw config
    if [ -f "$OPENCLAW_HOME/config.json" ]; then
        log_success "OpenClaw config exists at $OPENCLAW_HOME/config.json"
    else
        log_error "OpenClaw config not found"
        ERRORS=$((ERRORS + 1))
    fi

    # Check agent files
    AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_NAME"
    if [ -f "$AGENT_DIR/soul.md" ] && [ -f "$AGENT_DIR/memory.md" ] && [ -f "$AGENT_DIR/config.json" ]; then
        log_success "${AGENT_NAME} agent files configured"
    else
        log_error "${AGENT_NAME} agent files missing"
        ERRORS=$((ERRORS + 1))
    fi

    return $ERRORS
}

# ============================================================================
# Print Summary
# ============================================================================
print_summary() {
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "<YOUR-EC2-IP>")

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

    if [ -n "$DOMAIN" ]; then
        echo -e "  🌐 Dashboard:   ${GREEN}https://${DOMAIN}${NC}"
    else
        echo -e "  🌐 Dashboard:   ${GREEN}http://${PUBLIC_IP}${NC}"
    fi

    echo -e "  🔧 Backend API: ${BLUE}http://localhost:${MC_BACKEND_PORT}/health${NC}"
    echo -e "  🤖 Gateway:     ${BLUE}ws://localhost:${OPENCLAW_GATEWAY_PORT}${NC}"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🔑 Credentials${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Gateway Token:  ${YELLOW}${GATEWAY_TOKEN}${NC}"
    echo -e "  Agent Name:     ${YELLOW}${AGENT_NAME}${NC}"
    echo -e "  AI Model:       ${YELLOW}${AI_MODEL}${NC}"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📋 Useful Commands${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}View all processes:${NC}    pm2 status"
    echo -e "  ${BOLD}View logs:${NC}             pm2 logs"
    echo -e "  ${BOLD}Restart all:${NC}           pm2 restart all"
    echo -e "  ${BOLD}Restart backend:${NC}       pm2 restart mc-backend"
    echo -e "  ${BOLD}Restart frontend:${NC}      pm2 restart mc-frontend"
    echo -e "  ${BOLD}Restart gateway:${NC}       pm2 restart openclaw-gateway"
    echo -e "  ${BOLD}Stop all:${NC}              pm2 stop all"
    echo -e "  ${BOLD}View gateway logs:${NC}     pm2 logs openclaw-gateway"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📂 Important Paths${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  OpenClaw Config:     ${BLUE}${OPENCLAW_HOME}/config.json${NC}"
    echo -e "  Agent Directory:     ${BLUE}${OPENCLAW_HOME}/agents/${AGENT_NAME}/${NC}"
    echo -e "  Agent Soul:          ${BLUE}${OPENCLAW_HOME}/agents/${AGENT_NAME}/soul.md${NC}"
    echo -e "  Agent Memory:        ${BLUE}${OPENCLAW_HOME}/agents/${AGENT_NAME}/memory.md${NC}"
    echo -e "  Mission Control:     ${BLUE}${MC_DIR}/${NC}"
    echo -e "  Backend .env:        ${BLUE}${MC_DIR}/.env${NC}"
    echo -e "  Frontend .env:       ${BLUE}${MC_DIR}/client/.env.local${NC}"
    echo -e "  PM2 Config:          ${BLUE}${MC_DIR}/ecosystem.config.js${NC}"
    echo -e "  Nginx Config:        ${BLUE}/etc/nginx/sites-available/mission-control${NC}"
    echo -e "  Logs Directory:      ${BLUE}${OPENCLAW_HOME}/logs/${NC}"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  ⚡ Quick Config Changes${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Change API key:${NC}"
    echo -e "    nano ${OPENCLAW_HOME}/config.json  # Edit 'api.key'"
    echo -e "    pm2 restart all"
    echo ""
    echo -e "  ${BOLD}Change AI model:${NC}"
    echo -e "    nano ${OPENCLAW_HOME}/config.json  # Edit 'agent.model'"
    echo -e "    pm2 restart openclaw-gateway"
    echo ""
    echo -e "  ${BOLD}Edit agent personality:${NC}"
    echo -e "    nano ${OPENCLAW_HOME}/agents/${AGENT_NAME}/soul.md"
    echo ""
    echo -e "  ${BOLD}Add SSL later:${NC}"
    echo -e "    sudo bash ${MC_DIR}/setup.sh --domain YOUR_DOMAIN --email YOUR_EMAIL"
    echo ""
    echo -e "${GREEN}${BOLD}  Happy building with ${AGENT_NAME}! 🤖${NC}"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║   🚀 OpenClaw + Mission Control — EC2 Setup Script         ║"
    echo "║   Agent: Jarvis | Dashboard: Mission Control               ║"
    echo "║                                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    parse_args "$@"
    check_root

    # Interactive API key prompt if not provided
    if [ -z "$API_KEY" ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}No API key provided.${NC}"
        echo -e "Enter your ${AI_PROVIDER} API key (or press Enter to skip):"
        read -r -s API_KEY_INPUT
        if [ -n "$API_KEY_INPUT" ]; then
            API_KEY="$API_KEY_INPUT"
            log_success "API key received"
        else
            log_warn "No API key. OpenClaw Gateway won't work until you add one."
        fi
        echo ""
    fi

    # Generate Gateway Token
    GATEWAY_TOKEN=$(generate_token)

    # Run all phases
    install_system_deps
    install_openclaw
    configure_agent
    deploy_mission_control
    setup_pm2
    setup_nginx
    setup_ssl
    setup_firewall

    # Verify
    verify_setup

    # Print summary
    print_summary

    # Save setup info for future reference
    cat > "$OPENCLAW_HOME/setup-info.txt" << SETUPINFOEOF
Setup Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Agent Name: ${AGENT_NAME}
AI Model: ${AI_MODEL}
AI Provider: ${AI_PROVIDER}
Gateway Port: ${OPENCLAW_GATEWAY_PORT}
Gateway Token: ${GATEWAY_TOKEN}
Backend Port: ${MC_BACKEND_PORT}
Frontend Port: ${MC_FRONTEND_PORT}
Public IP: ${PUBLIC_IP}
Domain: ${DOMAIN:-none}
GitHub Repo: ${GITHUB_REPO}
SETUPINFOEOF
    chown ubuntu:ubuntu "$OPENCLAW_HOME/setup-info.txt"
}

# Run!
main "$@"
