'use client';

import { useState, useEffect } from 'react';

export default function MemoryPanel() {
  const [files, setFiles] = useState<any[]>([]);

  useEffect(() => {
    fetchMemory();
    const interval = setInterval(fetchMemory, 15000);
    return () => clearInterval(interval);
  }, []);

  const fetchMemory = async () => {
    try {
      const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001';
      const response = await fetch(`${apiUrl}/api/memory`);
      const data = await response.json();
      setFiles(data.files || []);
    } catch (error) {
      console.error('Error fetching memory:', error);
    }
  };

  return (
    <div className="bg-gray-800/50 backdrop-blur-sm rounded-lg p-6 border border-blue-500/30">
      <h2 className="text-xl font-bold mb-4">🧠 Memory Files</h2>
      
      {files.length === 0 ? (
        <p className="text-gray-400 text-sm">No memory files</p>
      ) : (
        <div className="space-y-2">
          {files.map((file, idx) => (
            <div
              key={idx}
              className="bg-gray-900/50 border border-gray-700 rounded-lg p-3 text-sm"
            >
              <div className="font-semibold text-blue-400 mb-1">📄 {file.name}</div>
              <div className="flex justify-between text-xs text-gray-400">
                <span>{file.size}</span>
                <span>{new Date(file.lastModified).toLocaleDateString()}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
