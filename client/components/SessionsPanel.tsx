'use client';

import { useState, useEffect } from 'react';

export default function SessionsPanel() {
  const [sessions, setSessions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [gatewayStatus, setGatewayStatus] = useState<string>('unknown');

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
      setGatewayStatus(data.gatewayStatus || 'connected');
      setError(data.error || null);
      setLoading(false);
    } catch (error) {
      console.error('Error fetching sessions:', error);
      setError('Failed to connect to backend');
      setLoading(false);
    }
  };

  const formatTimestamp = (ts: string) => {
    if (!ts) return 'N/A';
    try {
      const date = new Date(ts);
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffMins = Math.floor(diffMs / 60000);
      const diffHours = Math.floor(diffMins / 60);
      const diffDays = Math.floor(diffHours / 24);

      if (diffMins < 1) return 'just now';
      if (diffMins < 60) return `${diffMins}m ago`;
      if (diffHours < 24) return `${diffHours}h ago`;
      return `${diffDays}d ago`;
    } catch {
      return ts;
    }
  };

  const formatTokens = (session: any) => {
    if (session.tokens) {
      const used = session.tokens.used || session.tokens;
      const limit = session.tokens.limit;
      if (typeof used === 'number' && typeof limit === 'number') {
        return `${used.toLocaleString()} / ${limit.toLocaleString()}`;
      }
      if (typeof used === 'number') return used.toLocaleString();
    }
    if (session.tokenCount) return session.tokenCount.toLocaleString();
    return null;
  };

  return (
    <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">💬 Sessions</h2>
        {gatewayStatus !== 'connected' && (
          <span className="text-xs px-2 py-1 rounded-full bg-yellow-500/20 text-yellow-400 border border-yellow-500/30">
            {gatewayStatus}
          </span>
        )}
      </div>

      {loading ? (
        <div className="flex items-center gap-2 text-gray-400 text-sm">
          <div className="h-4 w-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
          Connecting to gateway...
        </div>
      ) : error ? (
        <div className="text-sm">
          <p className="text-yellow-400 mb-1">⚠️ {error}</p>
          {sessions.length > 0 && (
            <p className="text-gray-500 text-xs">Showing cached data</p>
          )}
        </div>
      ) : sessions.length === 0 ? (
        <p className="text-gray-400 text-sm">No sessions found</p>
      ) : null}

      {sessions.length > 0 && (
        <div className="space-y-3">
          {sessions.map((session, idx) => (
            <div
              key={session.key || session.id || idx}
              className="bg-gray-900/50 border border-gray-700 rounded-lg p-3"
            >
              <div className="flex justify-between items-start mb-2">
                <div className="flex items-center gap-2">
                  <div className={`h-2 w-2 rounded-full ${session.active !== false ? 'bg-green-500' : 'bg-gray-500'
                    }`} />
                  <span className="font-semibold text-blue-400">
                    {session.key || session.id || `Session ${idx + 1}`}
                  </span>
                </div>
                {session.kind && (
                  <span className="text-xs px-2 py-0.5 rounded-full bg-gray-700 text-gray-300">
                    {session.kind}
                  </span>
                )}
              </div>

              {session.label && (
                <div className="text-xs text-gray-400 mb-1">
                  {session.label}
                </div>
              )}

              <div className="grid grid-cols-2 gap-2 text-xs text-gray-400">
                {session.updated && (
                  <div>
                    <span className="text-gray-500">Updated: </span>
                    {formatTimestamp(session.updated)}
                  </div>
                )}

                {formatTokens(session) && (
                  <div>
                    <span className="text-gray-500">Tokens: </span>
                    {formatTokens(session)}
                  </div>
                )}

                {session.messages !== undefined && (
                  <div>
                    <span className="text-gray-500">Messages: </span>
                    {session.messages}
                  </div>
                )}
              </div>

              {/* Settings row */}
              {(session.thinking || session.verbose || session.reasoning) && (
                <div className="flex gap-2 mt-2 flex-wrap">
                  {session.thinking && (
                    <span className="text-xs px-2 py-0.5 rounded bg-purple-500/20 text-purple-300 border border-purple-500/30">
                      🧠 {session.thinking}
                    </span>
                  )}
                  {session.verbose && (
                    <span className="text-xs px-2 py-0.5 rounded bg-cyan-500/20 text-cyan-300 border border-cyan-500/30">
                      📝 {session.verbose}
                    </span>
                  )}
                  {session.reasoning && (
                    <span className="text-xs px-2 py-0.5 rounded bg-orange-500/20 text-orange-300 border border-orange-500/30">
                      💡 {session.reasoning}
                    </span>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
