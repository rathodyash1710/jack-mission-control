'use client';

import { useState, useEffect } from 'react';

export default function SessionsPanel() {
  const [sessions, setSessions] = useState<any[]>([]);

  useEffect(() => {
    fetchSessions();
    const interval = setInterval(fetchSessions, 10000);
    return () => clearInterval(interval);
  }, []);

  const fetchSessions = async () => {
    try {
      const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001';
      const response = await fetch(`${apiUrl}/api/sessions`);
      const data = await response.json();
      setSessions(data.sessions || []);
    } catch (error) {
      console.error('Error fetching sessions:', error);
    }
  };

  return (
    <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
      <h2 className="text-xl font-bold mb-4">💬 Sessions</h2>
      
      {sessions.length === 0 ? (
        <p className="text-gray-400 text-sm">No sessions found</p>
      ) : (
        <div className="space-y-3">
          {sessions.map((session) => (
            <div
              key={session.id}
              className="bg-gray-900/50 border border-gray-700 rounded-lg p-3"
            >
              <div className="flex justify-between items-start mb-2">
                <div className="flex items-center gap-2">
                  <div className={`h-2 w-2 rounded-full ${session.active ? 'bg-green-500' : 'bg-gray-500'}`} />
                  <span className="font-semibold">{session.label}</span>
                </div>
                <span className="text-xs text-gray-400">{session.id}</span>
              </div>
              <div className="text-sm text-gray-400">
                {session.messages} messages
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
