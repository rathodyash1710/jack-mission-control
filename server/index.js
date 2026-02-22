const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');
const http = require('http');
const crypto = require('crypto');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());

// Clawdbot Gateway Configuration
const CLAWDBOT_GATEWAY = process.env.CLAWDBOT_GATEWAY || 'ws://127.0.0.1:18789';
const GATEWAY_TOKEN = process.env.GATEWAY_TOKEN || '';

// Create HTTP server
const server = http.createServer(app);

// WebSocket Server for dashboard clients
// Accepts connections on both "/" (direct) and "/ws" (Nginx proxy)
const wss = new WebSocket.Server({
  server,
  verifyClient: (info) => {
    // Accept connections from any path (supports both direct and proxied)
    const path = info.req.url;
    return path === '/' || path === '/ws' || path.startsWith('/ws?') || path.startsWith('/?');
  }
});

// Store connected dashboard clients
const clients = new Set();

// ============================================================
// OpenClaw Gateway Connection Manager
// ============================================================

let gatewayWs = null;
let gatewayConnected = false;
let gatewayState = {
  status: 'disconnected',
  agent: null,
  health: null,
  presence: null,
  uptimeMs: 0,
  stateVersion: null,
  sessions: [],
  nodes: [],
  limits: null,
  policy: null,
  connectedAt: null,
};
let pendingRequests = new Map(); // id -> {resolve, reject, timeout}
let reconnectTimer = null;
let reconnectDelay = 1000; // Start with 1s, exponential backoff
const MAX_RECONNECT_DELAY = 30000;
let requestIdCounter = 0;

function generateRequestId() {
  return `req_${++requestIdCounter}_${Date.now()}`;
}

// Send a request to the OpenClaw Gateway and wait for response
function sendGatewayRequest(method, params = {}) {
  return new Promise((resolve, reject) => {
    if (!gatewayWs || gatewayWs.readyState !== WebSocket.OPEN) {
      reject(new Error('Gateway not connected'));
      return;
    }

    const id = generateRequestId();
    const timeout = setTimeout(() => {
      pendingRequests.delete(id);
      reject(new Error(`Gateway request timeout: ${method}`));
    }, 15000);

    pendingRequests.set(id, { resolve, reject, timeout });

    const frame = JSON.stringify({ type: 'req', id, method, params });
    console.log(`📤 Gateway REQ: ${method} (${id})`);
    gatewayWs.send(frame);
  });
}

// Connect to OpenClaw Gateway
function connectToGateway() {
  if (gatewayWs && (gatewayWs.readyState === WebSocket.OPEN || gatewayWs.readyState === WebSocket.CONNECTING)) {
    return;
  }

  // Determine the WebSocket URL
  let wsUrl = CLAWDBOT_GATEWAY;
  // If it starts with https, convert to wss
  if (wsUrl.startsWith('https://')) {
    wsUrl = wsUrl.replace('https://', 'wss://');
  } else if (wsUrl.startsWith('http://')) {
    wsUrl = wsUrl.replace('http://', 'ws://');
  }
  // Ensure it doesn't end with /
  wsUrl = wsUrl.replace(/\/+$/, '');
  // Append /ws endpoint and pass token as password query param
  wsUrl = `${wsUrl}/ws?password=${GATEWAY_TOKEN}`;

  console.log(`🔗 Connecting to OpenClaw Gateway: ${wsUrl.replace(GATEWAY_TOKEN, '***')}`);
  gatewayState.status = 'connecting';
  broadcastStatus();

  try {
    gatewayWs = new WebSocket(wsUrl, {
      headers: {
        'User-Agent': 'jack-mission-control/1.0.0',
      },
      rejectUnauthorized: false, // For self-signed certs on remote servers
    });
  } catch (err) {
    console.error('❌ Failed to create WebSocket:', err.message);
    scheduleReconnect();
    return;
  }

  gatewayWs.on('open', () => {
    console.log('🔌 WebSocket open to Gateway, waiting for challenge...');
    reconnectDelay = 1000; // Reset backoff on successful connect

    // The Gateway sends a connect.challenge event first.
    // We wait for it in the message handler.
    // If no challenge arrives (older protocol), send connect after a brief delay.
    setTimeout(() => {
      if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN && !gatewayConnected) {
        console.log('⏳ No challenge received, sending connect directly...');
        sendConnectHandshake(null);
      }
    }, 3000);
  });

  gatewayWs.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (err) {
      console.error('❌ Failed to parse gateway message:', raw.toString().substring(0, 200));
      return;
    }

    handleGatewayMessage(data);
  });

  gatewayWs.on('close', (code, reason) => {
    const reasonStr = reason ? reason.toString() : '';
    console.log(`⚠️ Gateway connection closed: code=${code} reason=${reasonStr}`);
    gatewayConnected = false;
    gatewayState.status = 'disconnected';
    broadcastStatus();

    // Reject all pending requests
    for (const [id, req] of pendingRequests) {
      clearTimeout(req.timeout);
      req.reject(new Error('Gateway connection closed'));
    }
    pendingRequests.clear();

    scheduleReconnect();
  });

  gatewayWs.on('unexpected-response', (req, res) => {
    let body = '';
    res.on('data', (chunk) => { body += chunk; });
    res.on('end', () => {
      console.error(`❌ Gateway unexpected HTTP response: ${res.statusCode} ${res.statusMessage}`);
      console.error(`   Headers:`, JSON.stringify(res.headers));
      console.error(`   Body: ${body.substring(0, 500)}`);
    });
  });

  gatewayWs.on('error', (err) => {
    console.error('❌ Gateway WebSocket error:', err.message);
  });
}

function sendConnectHandshake(nonce) {
  const connectReq = {
    type: 'req',
    id: generateRequestId(),
    method: 'connect',
    params: {
      minProtocol: 3,
      maxProtocol: 3,
      client: {
        id: 'jack-mission-control',
        version: '1.0.0',
        platform: 'web',
        mode: 'operator',
      },
      role: 'operator',
      scopes: ['operator.read', 'operator.write'],
      caps: [],
      commands: [],
      permissions: {},
      auth: {
        token: GATEWAY_TOKEN,
      },
      locale: 'en-US',
      userAgent: 'jack-mission-control/1.0.0',
    },
  };

  // If we received a challenge nonce, include device info
  if (nonce) {
    connectReq.params.device = {
      id: 'jack-mission-control-device',
      nonce: nonce,
    };
  }

  console.log('🤝 Sending connect handshake...');

  // Store as pending request to handle hello-ok response
  const id = connectReq.id;
  pendingRequests.set(id, {
    resolve: (payload) => {
      console.log('✅ Gateway handshake complete!');
      gatewayConnected = true;
      gatewayState.status = 'connected';
      gatewayState.connectedAt = new Date().toISOString();

      // Extract initial state from hello-ok
      if (payload) {
        if (payload.protocol) gatewayState.protocol = payload.protocol;
        if (payload.policy) gatewayState.policy = payload.policy;
        if (payload.presence) gatewayState.presence = payload.presence;
        if (payload.health) gatewayState.health = payload.health;
        if (payload.stateVersion) gatewayState.stateVersion = payload.stateVersion;
        if (payload.uptimeMs) gatewayState.uptimeMs = payload.uptimeMs;
        if (payload.limits) gatewayState.limits = payload.limits;
        // Extract nodes from presence
        if (payload.presence && payload.presence.nodes) {
          gatewayState.nodes = payload.presence.nodes;
        }
      }

      broadcastStatus();

      // Fetch initial data
      fetchSessionsFromGateway();
    },
    reject: (err) => {
      console.error('❌ Gateway handshake failed:', err.message);
      gatewayState.status = 'auth_failed';
      broadcastStatus();
    },
    timeout: setTimeout(() => {
      pendingRequests.delete(id);
      console.error('❌ Gateway handshake timeout');
      gatewayState.status = 'timeout';
      broadcastStatus();
    }, 15000),
  });

  gatewayWs.send(JSON.stringify(connectReq));
}

function handleGatewayMessage(data) {
  // Handle events
  if (data.type === 'event') {
    handleGatewayEvent(data);
    return;
  }

  // Handle responses
  if (data.type === 'res') {
    const pending = pendingRequests.get(data.id);
    if (pending) {
      clearTimeout(pending.timeout);
      pendingRequests.delete(data.id);

      if (data.ok) {
        pending.resolve(data.payload);
      } else {
        pending.reject(new Error(data.error?.message || `Gateway error: ${JSON.stringify(data.error)}`));
      }
    } else {
      console.log(`📨 Gateway RES (no pending): ${data.id}`, JSON.stringify(data).substring(0, 200));
    }
    return;
  }

  console.log(`📩 Gateway msg (${data.type}):`, JSON.stringify(data).substring(0, 200));
}

function handleGatewayEvent(data) {
  const event = data.event;

  switch (event) {
    case 'connect.challenge':
      console.log('🔐 Received connect challenge');
      sendConnectHandshake(data.payload?.nonce);
      break;

    case 'health':
      gatewayState.health = data.payload;
      broadcastStatus();
      break;

    case 'presence':
    case 'system-presence':
      if (data.payload) {
        gatewayState.presence = data.payload;
        if (data.payload.nodes) {
          gatewayState.nodes = data.payload.nodes;
        }
      }
      broadcastStatus();
      break;

    case 'tick':
    case 'heartbeat':
      // Keep-alive events, update uptime if provided
      if (data.payload?.uptimeMs) {
        gatewayState.uptimeMs = data.payload.uptimeMs;
      }
      // Send heartbeat back
      if (gatewayWs && gatewayWs.readyState === WebSocket.OPEN) {
        gatewayWs.send(JSON.stringify({ type: 'event', event: 'heartbeat' }));
      }
      break;

    case 'agent':
      // Agent activity event — forward to dashboard
      broadcast({ type: 'agentEvent', data: data.payload });
      break;

    case 'chat':
      // Chat event
      broadcast({ type: 'chatEvent', data: data.payload });
      break;

    case 'shutdown':
      console.log('⚠️ Gateway shutdown event received');
      gatewayState.status = 'shutting_down';
      broadcastStatus();
      break;

    default:
      console.log(`📩 Gateway event: ${event}`, JSON.stringify(data.payload || {}).substring(0, 150));
      // Broadcast unknown events to dashboard for visibility
      broadcast({ type: 'gatewayEvent', event, data: data.payload });
      break;
  }

  // Track state version
  if (data.stateVersion) {
    gatewayState.stateVersion = data.stateVersion;
  }
  if (data.seq !== undefined) {
    gatewayState.lastSeq = data.seq;
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;

  console.log(`🔄 Reconnecting in ${reconnectDelay / 1000}s...`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectToGateway();
  }, reconnectDelay);

  // Exponential backoff
  reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY);
}

// Fetch sessions from gateway
async function fetchSessionsFromGateway() {
  try {
    const result = await sendGatewayRequest('sessions.list', {});
    gatewayState.sessions = result?.sessions || result || [];
    console.log(`📋 Fetched ${Array.isArray(gatewayState.sessions) ? gatewayState.sessions.length : 0} sessions`);
    return gatewayState.sessions;
  } catch (err) {
    console.error('❌ Failed to fetch sessions:', err.message);
    return [];
  }
}

// ============================================================
// Dashboard WebSocket Server (for browser clients)
// ============================================================

wss.on('connection', (ws) => {
  console.log('🖥️ Dashboard client connected');
  clients.add(ws);

  ws.on('message', async (message) => {
    try {
      const data = JSON.parse(message);
      console.log('📥 Dashboard command:', data);

      switch (data.type) {
        case 'command':
          await handleCommand(data.payload);
          break;
        case 'getStatus':
          ws.send(JSON.stringify({ type: 'status', data: buildStatusPayload() }));
          break;
      }
    } catch (error) {
      console.error('Error processing dashboard message:', error);
      ws.send(JSON.stringify({ type: 'error', message: error.message }));
    }
  });

  ws.on('close', () => {
    console.log('🖥️ Dashboard client disconnected');
    clients.delete(ws);
  });

  // Send initial status
  ws.send(JSON.stringify({ type: 'status', data: buildStatusPayload() }));
});

// Build status payload for dashboard
function buildStatusPayload() {
  const uptimeSeconds = gatewayState.uptimeMs
    ? gatewayState.uptimeMs / 1000
    : (gatewayState.connectedAt
      ? (Date.now() - new Date(gatewayState.connectedAt).getTime()) / 1000
      : 0);

  // Extract agent info from nodes/presence
  let agentName = 'Unknown';
  let agentModel = 'N/A';
  let activeNodes = 0;

  if (gatewayState.nodes && gatewayState.nodes.length > 0) {
    activeNodes = gatewayState.nodes.length;
    const firstNode = gatewayState.nodes[0];
    agentName = firstNode.agent || firstNode.name || firstNode.id || 'Agent';
    agentModel = firstNode.model || 'N/A';
  }

  // Extract from presence if available
  if (gatewayState.presence) {
    if (gatewayState.presence.agent) agentName = gatewayState.presence.agent;
    if (gatewayState.presence.model) agentModel = gatewayState.presence.model;
  }

  // Extract from health
  if (gatewayState.health) {
    if (gatewayState.health.agent) agentName = gatewayState.health.agent;
    if (gatewayState.health.model) agentModel = gatewayState.health.model;
  }

  return {
    agent: agentName,
    status: gatewayState.status === 'connected' ? 'online' : gatewayState.status,
    gatewayStatus: gatewayState.status,
    model: agentModel,
    uptime: uptimeSeconds,
    sessions: {
      active: Array.isArray(gatewayState.sessions)
        ? gatewayState.sessions.filter(s => s.active !== false).length
        : 0,
      total: Array.isArray(gatewayState.sessions) ? gatewayState.sessions.length : 0,
    },
    nodes: activeNodes,
    health: gatewayState.health,
    presence: gatewayState.presence,
    stateVersion: gatewayState.stateVersion,
    lastActivity: new Date().toISOString(),
    limits: gatewayState.limits,
    policy: gatewayState.policy,
  };
}

// Broadcast to all connected dashboard clients
function broadcast(data) {
  const message = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

function broadcastStatus() {
  broadcast({ type: 'statusUpdate', data: buildStatusPayload() });
}

// Handle commands from dashboard
async function handleCommand(command) {
  console.log('🎮 Executing command:', command);

  try {
    switch (command.action) {
      case 'status':
        broadcastStatus();
        break;

      case 'sessions':
        await fetchSessionsFromGateway();
        broadcastStatus();
        break;

      case 'reconnect':
        // Force reconnect to gateway
        if (gatewayWs) {
          gatewayWs.close();
        }
        gatewayState.status = 'reconnecting';
        broadcastStatus();
        setTimeout(connectToGateway, 500);
        break;

      case 'message':
        // Forward message to gateway as a chat request
        if (gatewayConnected) {
          try {
            const result = await sendGatewayRequest('chat.send', {
              message: command.content,
              sessionKey: command.sessionKey || 'default',
            });
            broadcast({ type: 'commandResult', command, result });
          } catch (err) {
            broadcast({ type: 'error', message: `Failed to send message: ${err.message}` });
          }
        } else {
          broadcast({ type: 'error', message: 'Gateway not connected' });
        }
        break;

      default:
        // Forward unknown commands to gateway as generic requests
        if (gatewayConnected) {
          try {
            const result = await sendGatewayRequest(command.action, command.params || {});
            broadcast({ type: 'commandResult', command, result });
          } catch (err) {
            broadcast({ type: 'error', message: `Command failed: ${err.message}` });
          }
        }
        break;
    }
  } catch (error) {
    console.error('Command error:', error);
    broadcast({ type: 'commandExecuted', command, error: error.message });
  }
}

// ============================================================
// REST API Endpoints
// ============================================================

app.get('/api/status', async (req, res) => {
  res.json(buildStatusPayload());
});

app.post('/api/command', async (req, res) => {
  try {
    await handleCommand(req.body);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/sessions', async (req, res) => {
  try {
    // Always fetch fresh data from gateway
    if (gatewayConnected) {
      const sessions = await fetchSessionsFromGateway();
      res.json({ sessions: Array.isArray(sessions) ? sessions : [] });
    } else {
      // Return cached sessions or empty
      res.json({
        sessions: Array.isArray(gatewayState.sessions) ? gatewayState.sessions : [],
        cached: true,
        gatewayStatus: gatewayState.status,
      });
    }
  } catch (error) {
    console.error('Error fetching sessions:', error);
    res.json({
      sessions: Array.isArray(gatewayState.sessions) ? gatewayState.sessions : [],
      error: error.message,
      gatewayStatus: gatewayState.status,
    });
  }
});

app.get('/api/memory', async (req, res) => {
  try {
    if (gatewayConnected) {
      // Try to fetch memory data from gateway
      try {
        const result = await sendGatewayRequest('memory.list', {});
        res.json({ files: result?.files || result || [] });
      } catch (err) {
        // memory.list may not be a supported method, try alternatives
        console.log('memory.list not available, trying state.memory...');
        try {
          const result = await sendGatewayRequest('state.memory', {});
          res.json({ files: result?.files || result || [] });
        } catch (err2) {
          res.json({
            files: [],
            note: 'Memory API not available on this gateway',
            gatewayStatus: gatewayState.status,
          });
        }
      }
    } else {
      res.json({
        files: [],
        gatewayStatus: gatewayState.status,
      });
    }
  } catch (error) {
    res.json({ files: [], error: error.message });
  }
});

// Gateway info endpoint
app.get('/api/gateway', async (req, res) => {
  res.json({
    url: CLAWDBOT_GATEWAY,
    status: gatewayState.status,
    connected: gatewayConnected,
    connectedAt: gatewayState.connectedAt,
    stateVersion: gatewayState.stateVersion,
    protocol: gatewayState.protocol,
    nodes: gatewayState.nodes,
    health: gatewayState.health,
    presence: gatewayState.presence,
    limits: gatewayState.limits,
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    gateway: gatewayState.status,
    gatewayConnected,
    timestamp: new Date().toISOString(),
  });
});

// ============================================================
// Start Server
// ============================================================

server.listen(PORT, () => {
  console.log(`\n🚀 Jack Mission Control Backend running on port ${PORT}`);
  console.log(`📡 WebSocket server ready for dashboard clients`);
  console.log(`🔗 OpenClaw Gateway target: ${CLAWDBOT_GATEWAY}`);
  console.log(`🔑 Gateway token: ${GATEWAY_TOKEN ? GATEWAY_TOKEN.substring(0, 8) + '...' : 'NOT SET'}\n`);

  // Connect to OpenClaw Gateway
  connectToGateway();
});

// Periodic status broadcast to dashboard clients (every 10 seconds)
setInterval(() => {
  if (clients.size > 0) {
    broadcastStatus();
  }
}, 10000);

// Periodic session refresh (every 30 seconds)
setInterval(async () => {
  if (gatewayConnected) {
    await fetchSessionsFromGateway();
  }
}, 30000);
