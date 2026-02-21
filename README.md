# 🚀 Jack Mission Control

**Live Mission Control Dashboard for Jack Clawdbot Agent**

Real-time monitoring and control interface for your Clawdbot AI agent.

---

## 🎯 Features

- **Real-Time Status** - Live agent health, uptime, model info
- **Session Management** - View all active and past sessions
- **Memory Monitor** - Track memory files and usage
- **Command Center** - Send commands and messages to Jack
- **Activity Logs** - Live event stream
- **WebSocket Updates** - Instant status updates every 5 seconds

---

## 🏗️ Architecture

```
┌─────────────┐         WebSocket/REST         ┌──────────────┐
│   Browser   │ ←─────────────────────────────→ │   Backend    │
│  (Next.js)  │                                 │  (Node.js)   │
└─────────────┘                                 └──────┬───────┘
                                                       │
                                                       ▼
                                                ┌──────────────┐
                                                │  Clawdbot    │
                                                │   Gateway    │
                                                └──────────────┘
```

**Components:**
- **Frontend**: Next.js 14 + React + TypeScript + Tailwind CSS
- **Backend**: Node.js + Express + WebSocket (ws)
- **Integration**: Clawdbot Gateway API
- **Hosting**: Vercel (frontend) + Railway (backend)

---

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- npm or pnpm
- Clawdbot installed and running

### 1. Install Dependencies

```bash
# Install backend
npm install

# Install frontend
cd client
npm install
```

### 2. Configure Environment

Create `.env` in root:
```env
PORT=3001
CLAWDBOT_GATEWAY=http://127.0.0.1:18789
GATEWAY_TOKEN=your-gateway-token-here
```

Create `client/.env.local`:
```env
NEXT_PUBLIC_API_URL=http://localhost:3001
NEXT_PUBLIC_WS_URL=ws://localhost:3001
```

### 3. Run Locally

**Option A: Run both together**
```bash
npm run dev
```

**Option B: Run separately**
```bash
# Terminal 1 - Backend
npm run server:dev

# Terminal 2 - Frontend
cd client
npm run dev
```

### 4. Access Dashboard

Open **http://localhost:3000** in your browser.

---

## 📡 API Endpoints

### REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/status` | Get current agent status |
| GET | `/api/sessions` | List all sessions |
| GET | `/api/memory` | Get memory files info |
| POST | `/api/command` | Send command to agent |
| GET | `/health` | Health check |

### WebSocket Events

**Client → Server:**
```json
{
  "type": "command",
  "payload": { "action": "status" }
}
```

**Server → Client:**
```json
{
  "type": "statusUpdate",
  "data": { "agent": "Jack", "status": "online", ... }
}
```

---

## 🌐 Deployment

### Deploy to Vercel (Frontend)

```bash
cd client
npm install -g vercel
vercel --prod
```

### Deploy to Railway (Backend)

1. Create new project on [Railway](https://railway.app)
2. Connect this repo
3. Set environment variables
4. Deploy

Or use the button:

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template?template=https://github.com/Yash-AIML/jack-mission-control)

### Environment Variables for Production

**Backend (Railway):**
- `PORT` - Auto-set by Railway
- `CLAWDBOT_GATEWAY` - Your Clawdbot gateway URL
- `GATEWAY_TOKEN` - Your gateway auth token

**Frontend (Vercel):**
- `NEXT_PUBLIC_API_URL` - Your Railway backend URL
- `NEXT_PUBLIC_WS_URL` - Your Railway WebSocket URL (wss://)

---

## 📂 Project Structure

```
jack-mission-control/
├── server/
│   └── index.js              # Backend server (Express + WebSocket)
├── client/
│   ├── app/
│   │   ├── page.tsx          # Main dashboard
│   │   ├── layout.tsx        # App layout
│   │   └── globals.css       # Global styles
│   ├── components/
│   │   ├── StatusPanel.tsx   # Agent status display
│   │   ├── CommandPanel.tsx  # Control interface
│   │   ├── SessionsPanel.tsx # Sessions list
│   │   ├── MemoryPanel.tsx   # Memory files
│   │   └── ActivityLog.tsx   # Event log
│   └── package.json
├── package.json
├── .env.example
└── README.md
```

---

## 🔧 Integration with Clawdbot

The backend connects to your Clawdbot instance via the Gateway API.

**Current Integration Points:**
- Status monitoring (sessions, memory, uptime)
- Command execution
- Session management
- Memory file tracking

**To extend integration:**

Edit `server/index.js` and add your custom Clawdbot API calls:

```javascript
async function getClawdbotStatus() {
  const response = await axios.get(`${CLAWDBOT_GATEWAY}/api/status`, {
    headers: { Authorization: `Bearer ${GATEWAY_TOKEN}` }
  });
  return response.data;
}
```

---

## 🎨 Customization

### Add New Widgets

1. Create component in `client/components/YourWidget.tsx`
2. Import in `client/app/page.tsx`
3. Add to dashboard grid

### Add New Commands

Edit `client/components/CommandPanel.tsx`:

```typescript
const quickCommands = [
  { label: 'Your Command', action: 'yourAction', icon: '🎯' },
  // ... existing commands
];
```

Handle in `server/index.js`:

```javascript
async function handleCommand(command) {
  if (command.action === 'yourAction') {
    // Your logic here
  }
}
```

---

## 🛠️ Tech Stack

- **Frontend**: Next.js 14, React 18, TypeScript, Tailwind CSS
- **Backend**: Node.js, Express, WebSocket (ws)
- **Deployment**: Vercel, Railway
- **Real-time**: WebSocket for bi-directional communication

---

## 📊 Features Roadmap

- [x] Real-time status monitoring
- [x] WebSocket communication
- [x] Command execution
- [x] Activity logging
- [ ] Video feed integration
- [ ] Advanced analytics dashboard
- [ ] Mobile app (React Native)
- [ ] Multi-agent support
- [ ] Historical data & charts
- [ ] Alert notifications

---

## 🆘 Troubleshooting

### WebSocket Connection Failed

- Check backend is running on correct port
- Verify `NEXT_PUBLIC_WS_URL` in frontend env
- Check firewall/CORS settings

### Clawdbot Gateway Connection Error

- Verify `CLAWDBOT_GATEWAY` URL is correct
- Check `GATEWAY_TOKEN` matches your Clawdbot config
- Ensure Clawdbot gateway is running (`clawdbot status`)

### Dependencies Installation Fails

```bash
rm -rf node_modules package-lock.json
npm install
```

---

## 📝 License

MIT License - Created by Yash for Jack Clawdbot Agent

---

## 🤝 Contributing

Want to add features? Fork, modify, and submit a PR!

---

**Built with ❤️ for Jack the Clawdbot Agent**
