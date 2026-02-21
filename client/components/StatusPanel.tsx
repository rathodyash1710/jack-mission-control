export default function StatusPanel({ status }: { status: any }) {
  if (!status) {
    return (
      <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
        <h2 className="text-xl font-bold mb-4">🔄 Agent Status</h2>
        <p className="text-gray-400">Loading...</p>
      </div>
    );
  }

  return (
    <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
      <h2 className="text-xl font-bold mb-4">🔄 Agent Status</h2>
      
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard 
          label="Agent" 
          value={status.agent || 'Jack'} 
          icon="🤖"
          color="blue"
        />
        <StatCard 
          label="Status" 
          value={status.status || 'unknown'} 
          icon={status.status === 'online' ? '✅' : '⚠️'}
          color={status.status === 'online' ? 'green' : 'yellow'}
        />
        <StatCard 
          label="Model" 
          value={status.model?.split('/').pop() || 'N/A'} 
          icon="🧠"
          color="purple"
        />
        <StatCard 
          label="Uptime" 
          value={formatUptime(status.uptime || 0)} 
          icon="⏱️"
          color="cyan"
        />
      </div>

      <div className="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-gray-900/50 rounded-lg p-4 border border-gray-700">
          <h3 className="text-sm font-semibold text-gray-400 mb-2">Sessions</h3>
          <div className="flex justify-between items-center">
            <span className="text-2xl font-bold">{status.sessions?.active || 0}</span>
            <span className="text-sm text-gray-400">/ {status.sessions?.total || 0} total</span>
          </div>
        </div>

        <div className="bg-gray-900/50 rounded-lg p-4 border border-gray-700">
          <h3 className="text-sm font-semibold text-gray-400 mb-2">Memory</h3>
          <div className="flex justify-between items-center">
            <span className="text-2xl font-bold">{status.memory?.usage || 'N/A'}</span>
            <span className="text-sm text-gray-400">{status.memory?.files || 0} files</span>
          </div>
        </div>
      </div>

      <div className="mt-4 text-xs text-gray-500">
        Last update: {status.lastActivity ? new Date(status.lastActivity).toLocaleString() : 'N/A'}
      </div>
    </div>
  );
}

function StatCard({ label, value, icon, color }: any) {
  const colorClasses: any = {
    blue: 'border-blue-500/50 bg-blue-500/10',
    green: 'border-green-500/50 bg-green-500/10',
    yellow: 'border-yellow-500/50 bg-yellow-500/10',
    purple: 'border-purple-500/50 bg-purple-500/10',
    cyan: 'border-cyan-500/50 bg-cyan-500/10'
  };

  return (
    <div className={`rounded-lg p-4 border ${colorClasses[color] || colorClasses.blue}`}>
      <div className="text-2xl mb-1">{icon}</div>
      <div className="text-xs text-gray-400 mb-1">{label}</div>
      <div className="text-lg font-bold truncate">{value}</div>
    </div>
  );
}

function formatUptime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m`;
  return `${Math.floor(seconds)}s`;
}
