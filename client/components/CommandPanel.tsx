'use client';

import { useState } from 'react';

export default function CommandPanel({ onCommand }: { onCommand: (cmd: any) => void }) {
  const [message, setMessage] = useState('');

  const quickCommands = [
    { label: 'Get Status', action: 'status', icon: '📊' },
    { label: 'List Sessions', action: 'sessions', icon: '💬' },
    { label: 'View Memory', action: 'memory', icon: '🧠' },
    { label: 'Clear Logs', action: 'clearLogs', icon: '🗑️' },
  ];

  const handleQuickCommand = (action: string) => {
    onCommand({ action, timestamp: Date.now() });
  };

  const handleSendMessage = () => {
    if (message.trim()) {
      onCommand({ action: 'message', content: message, timestamp: Date.now() });
      setMessage('');
    }
  };

  return (
    <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
      <h2 className="text-xl font-bold mb-4">🎮 Control Panel</h2>

      {/* Quick Commands */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        {quickCommands.map((cmd) => (
          <button
            key={cmd.action}
            onClick={() => handleQuickCommand(cmd.action)}
            className="bg-blue-600 hover:bg-blue-700 transition-colors rounded-lg p-3 text-sm font-semibold flex flex-col items-center gap-1"
          >
            <span className="text-2xl">{cmd.icon}</span>
            <span>{cmd.label}</span>
          </button>
        ))}
      </div>

      {/* Message Input */}
      <div className="space-y-3">
        <label className="text-sm font-semibold text-gray-300">Send Message to Jack</label>
        <div className="flex gap-2">
          <input
            type="text"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && handleSendMessage()}
            placeholder="Type a message or command..."
            className="flex-1 bg-gray-900/50 border border-gray-700 rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500 transition-colors"
          />
          <button
            onClick={handleSendMessage}
            className="bg-green-600 hover:bg-green-700 transition-colors rounded-lg px-6 py-2 font-semibold"
          >
            Send
          </button>
        </div>
      </div>
    </div>
  );
}
