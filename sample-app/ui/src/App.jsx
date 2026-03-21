import { useState } from 'react'
import TasksTab from './components/TasksTab'
import AgentChatTab from './components/AgentChatTab'
import './index.css'

function App() {
  const [activeTab, setActiveTab] = useState('tasks')

  return (
    <div style={{ maxWidth: '800px', margin: '0 auto', padding: '20px' }}>
      <header style={{ marginBottom: '20px' }}>
        <h1>Agentic POC - Sample App</h1>
      </header>

      <div style={{ marginBottom: '20px', borderBottom: '1px solid #ddd' }}>
        <button
          onClick={() => setActiveTab('tasks')}
          style={{
            padding: '10px 20px',
            border: 'none',
            background: activeTab === 'tasks' ? '#007bff' : 'transparent',
            color: activeTab === 'tasks' ? 'white' : '#007bff',
            cursor: 'pointer',
            marginRight: '10px'
          }}
        >
          Tasks
        </button>
        <button
          onClick={() => setActiveTab('agent')}
          style={{
            padding: '10px 20px',
            border: 'none',
            background: activeTab === 'agent' ? '#007bff' : 'transparent',
            color: activeTab === 'agent' ? 'white' : '#007bff',
            cursor: 'pointer'
          }}
        >
          Agent Chat
        </button>
      </div>

      <div>
        {activeTab === 'tasks' && <TasksTab />}
        {activeTab === 'agent' && <AgentChatTab />}
      </div>
    </div>
  )
}

export default App
