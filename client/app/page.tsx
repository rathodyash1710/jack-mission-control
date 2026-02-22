'use client';

import { useState, useEffect } from 'react';
import StatusPanel from '@/components/StatusPanel';
import SessionsPanel from '@/components/SessionsPanel';
import MemoryPanel from '@/components/MemoryPanel';
import CommandPanel from '@/components/CommandPanel';
import ActivityLog from '@/components/ActivityLog';

export default function MissionControl() {
  const [status, setStatus] = useState<any>(null);
  const [ws, setWs] = useState<WebSocket | null>(null);
  const [connected, setConnected] = useState(false);
  const [logs, setLogs] = useState<string[]>([]);

  useEffect(() => {
    // Connect to WebSocket server
    // In production (behind Nginx), connect to /ws path
    // In development, connect directly to backend port
    const wsBase = process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost:3001';
    const wsUrl = wsBase.includes('localhost:3001') ? wsBase : `${wsBase}/ws`;
    const socket = new WebSocket(wsUrl);

    socket.onopen = () => {
      console.log('Connected to Mission Control');
      setConnected(true);
      addLog('✅ Connected to Jack Mission Control');
      socket.send(JSON.stringify({ type: 'getStatus' }));
    };

    socket.onmessage = (event) => {
      const data = JSON.parse(event.data);

      switch (data.type) {
        case 'status':
        case 'statusUpdate':
          setStatus(data.data);
          break;
        case 'commandExecuted':
          addLog(`🎯 Command executed: ${JSON.stringify(data.command)}`);
          break;
        case 'error':
          addLog(`❌ Error: ${data.message}`);
          break;
      }
    };

    socket.onclose = () => {
      console.log('Disconnected from Mission Control');
      setConnected(false);
      addLog('⚠️ Disconnected from Mission Control');
    };

    socket.onerror = (error) => {
      console.error('WebSocket error:', error);
      addLog('❌ Connection error');
    };

    setWs(socket);

    return () => {
      socket.close();
    };
  }, []);

  const addLog = (message: string) => {
    setLogs(prev => [`[${new Date().toLocaleTimeString()}] ${message}`, ...prev].slice(0, 100));
  };

  const sendCommand = (command: any) => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'command', payload: command }));
      addLog(`📤 Sent command: ${command.action}`);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-blue-900 to-gray-900 text-white">
      {/* Header */}
      <header className="border-b border-blue-500/30 bg-black/30 backdrop-blur-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <div className="text-3xl">🤖</div>
              <div>
                <h1 className="text-2xl font-bold">Jack Mission Control</h1>
                <p className="text-sm text-gray-400">Clawdbot Agent Dashboard</p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <div className={`h-3 w-3 rounded-full ${connected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`} />
              <span className="text-sm">{connected ? 'Connected' : 'Disconnected'}</span>
            </div>
          </div>
        </div>
      </header>

      {/* Main Dashboard */}
      <main className="container mx-auto px-4 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column */}
          <div className="lg:col-span-2 space-y-6">
            <StatusPanel status={status} />
            <CommandPanel onCommand={sendCommand} />
            <ActivityLog logs={logs} />
          </div>

          {/* Right Column */}
          <div className="space-y-6">
            <SessionsPanel />
            <MemoryPanel />
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="mt-12 border-t border-blue-500/30 bg-black/30 backdrop-blur-sm py-4">
        <div className="container mx-auto px-4 text-center text-sm text-gray-400">
          Jack Mission Control • Built for Clawdbot • {new Date().getFullYear()}
        </div>
      </footer>
    </div>
  );
}
