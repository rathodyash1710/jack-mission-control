export default function ActivityLog({ logs }: { logs: string[] }) {
  return (
    <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
      <h2 className="text-xl font-bold mb-4">📋 Activity Log</h2>
      
      <div className="bg-black/50 rounded-lg p-4 h-64 overflow-y-auto font-mono text-sm">
        {logs.length === 0 ? (
          <p className="text-gray-500">No activity yet...</p>
        ) : (
          logs.map((log, idx) => (
            <div key={idx} className="mb-1 text-gray-300 hover:bg-gray-800/50 px-2 py-1 rounded">
              {log}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
