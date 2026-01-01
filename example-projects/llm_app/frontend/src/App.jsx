import { useState, useRef, useEffect } from 'react'
import './App.css'

const API_URL = 'http://localhost:3000'

function App() {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState({ connected: false, modelLoaded: false })
  const messagesEndRef = useRef(null)

  // Check backend health on mount
  useEffect(() => {
    checkHealth()
  }, [])

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const checkHealth = async () => {
    try {
      const response = await fetch(`${API_URL}/api/health`)
      const data = await response.json()
      setStatus({ connected: true, modelLoaded: data.model_loaded })
    } catch (error) {
      setStatus({ connected: false, modelLoaded: false })
    }
  }

  const sendMessage = async (e) => {
    e.preventDefault()
    if (!input.trim() || loading) return

    const userMessage = input.trim()
    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: userMessage }])
    setLoading(true)

    try {
      const response = await fetch(`${API_URL}/api/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: userMessage })
      })
      const data = await response.json()

      if (data.error) {
        setMessages(prev => [...prev, { role: 'error', content: data.error }])
      } else {
        setMessages(prev => [...prev, {
          role: 'assistant',
          content: data.response,
          tokens: data.tokens_used
        }])
      }
    } catch (error) {
      setMessages(prev => [...prev, {
        role: 'error',
        content: 'Failed to connect to backend. Is the server running?'
      }])
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="app">
      <header className="header">
        <h1>Gene LLM Chat</h1>
        <div className="status">
          <span className={`dot ${status.connected ? 'connected' : 'disconnected'}`}></span>
          {status.connected
            ? (status.modelLoaded ? 'LLM Ready' : 'Mock Mode')
            : 'Disconnected'}
        </div>
      </header>

      <main className="chat-container">
        <div className="messages">
          {messages.length === 0 && (
            <div className="welcome">
              <p>Welcome to Gene LLM Chat!</p>
              <p className="hint">Send a message to start chatting.</p>
            </div>
          )}
          {messages.map((msg, idx) => (
            <div key={idx} className={`message ${msg.role}`}>
              <div className="message-content">{msg.content}</div>
              {msg.tokens && (
                <div className="message-meta">{msg.tokens} tokens</div>
              )}
            </div>
          ))}
          {loading && (
            <div className="message assistant loading">
              <div className="typing-indicator">
                <span></span><span></span><span></span>
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        <form className="input-form" onSubmit={sendMessage}>
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
      </main>
    </div>
  )
}

export default App
