import { useState, useRef, useEffect } from 'react'
import { api } from '../api/client'
import './AgentChatTab.css'

export default function AgentChatTab() {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const messagesEndRef = useRef(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!input.trim() || loading) return

    const userMessage = input
    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: userMessage }])
    setLoading(true)
    setError(null)

    try {
      const response = await api.sendChatMessage(userMessage)
      setMessages(prev => [...prev, {
        role: 'agent',
        content: response.message,
        isCalculation: response.is_calculation,
        mode: response.mode,
        directResponse: response.direct_response,
        codeResult: response.code_result,
        generatedPython: response.generated_python,
        executionBackend: response.execution_backend,
      }])
    } catch (err) {
      setError('Failed to get response: ' + err.message)
      setMessages(prev => [...prev, { role: 'agent', content: 'Sorry, I encountered an error.' }])
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="agent-chat-tab">
      {error && <div className="error">{error}</div>}

      <div className="chat-messages">
        {messages.length === 0 && (
          <div className="chat-empty">
            <p>Start a conversation with the AI agent!</p>
            <p>Ask anything and get a response powered by gpt-5.1-codex-mini.</p>
          </div>
        )}
        {messages.map((msg, idx) => (
          <div key={idx} className={`message message-${msg.role}`}>
            <div className="message-role">{msg.role === 'user' ? 'You' : 'Agent'}</div>
            <div className="message-content">
              <div>{msg.content}</div>
              {msg.role === 'agent' && msg.isCalculation && (
                <div className="calc-comparison">
                  <div className="calc-card">
                    <div className="calc-title">Approach A: Direct LLM Output</div>
                    <pre className="calc-pre">{msg.directResponse || 'N/A'}</pre>
                  </div>
                  <div className="calc-card">
                    <div className="calc-title">Approach B: Python Execution Output</div>
                    <pre className="calc-pre calc-pre-result">{msg.codeResult || 'N/A'}</pre>
                    {msg.executionBackend && (
                      <div className="calc-meta">Execution backend: {msg.executionBackend}</div>
                    )}
                  </div>
                  {msg.generatedPython && (
                    <details className="calc-code">
                      <summary>Generated Python Script</summary>
                      <pre>{msg.generatedPython}</pre>
                    </details>
                  )}
                </div>
              )}
            </div>
          </div>
        ))}
        {loading && (
          <div className="message message-agent">
            <div className="message-role">Agent</div>
            <div className="message-content loading">Thinking...</div>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      <form onSubmit={handleSubmit} className="chat-input">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Type your message..."
          disabled={loading}
        />
        <button type="submit" disabled={loading || !input.trim()}>
          Send
        </button>
      </form>
    </div>
  )
}
