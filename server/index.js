const express = require('express');
const WebSocket = require('ws');
const cors = require('cors');
const axios = require('axios');
const http = require('http');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());

// Clawdbot Gateway Configuration
const CLAWDBOT_GATEWAY = process.env.CLAWDBOT_GATEWAY || 'http://127.0.0.1:18789';
const GATEWAY_TOKEN = process.env.GATEWAY_TOKEN || 'f731a4b2b1ec84f3c532344d20ffbce97053cc95bae44731af66542ddaf9809d';

// Create HTTP server
const server = http.createServer(app);

// WebSocket Server
const wss = new WebSocket.Server({ server });

// Store connected clients
const clients = new Set();

wss.on('connection', (ws) => {
  console.log('New client connected');
  clients.add(ws);

  ws.on('message', async (message) => {
    try {
      const data = JSON.parse(message);
      console.log('Received:', data);

      // Handle different message types
      switch (data.type) {
        case 'command':
          await handleCommand(data.payload);
          break;
        case 'getStatus':
          const status = await getClawdbotStatus();
          ws.send(JSON.stringify({ type: 'status', data: status }));
          break;
      }
    } catch (error) {
      console.error('Error processing message:', error);
      ws.send(JSON.stringify({ type: 'error', message: error.message }));
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    clients.delete(ws);
  });

  // Send initial status
  getClawdbotStatus().then(status => {
    ws.send(JSON.stringify({ type: 'status', data: status }));
  });
});

// Broadcast to all connected clients
function broadcast(data) {
  const message = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Get Clawdbot status
async function getClawdbotStatus() {
  try {
    // This would connect to Clawdbot's actual API
    // For now, returning mock data - will integrate with real Clawdbot API
    return {
      agent: 'Jack',
      status: 'online',
      model: 'claude-sonnet-4-5',
      uptime: process.uptime(),
      sessions: {
        active: 1,
        total: 5
      },
      memory: {
        usage: '45MB',
        files: 8
      },
      lastActivity: new Date().toISOString()
    };
  } catch (error) {
    console.error('Error getting status:', error);
    return { status: 'error', message: error.message };
  }
}

// Handle commands from dashboard
async function handleCommand(command) {
  console.log('Executing command:', command);
  // Will integrate with Clawdbot session/command API
  broadcast({ type: 'commandExecuted', command });
}

// REST API Endpoints
app.get('/api/status', async (req, res) => {
  const status = await getClawdbotStatus();
  res.json(status);
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
  // Will integrate with Clawdbot sessions API
  res.json({
    sessions: [
      { id: 'main', label: 'Main Session', active: true, messages: 156 }
    ]
  });
});

app.get('/api/memory', async (req, res) => {
  // Will integrate to read memory files
  res.json({
    files: [
      { name: 'MEMORY.md', size: '12KB', lastModified: new Date() },
      { name: 'AGENTS.md', size: '8KB', lastModified: new Date() }
    ]
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Start server
server.listen(PORT, () => {
  console.log(`🚀 Jack Mission Control Backend running on port ${PORT}`);
  console.log(`📡 WebSocket server ready`);
  console.log(`🔗 Clawdbot Gateway: ${CLAWDBOT_GATEWAY}`);
});

// Periodic status broadcast (every 5 seconds)
setInterval(async () => {
  const status = await getClawdbotStatus();
  broadcast({ type: 'statusUpdate', data: status });
}, 5000);
