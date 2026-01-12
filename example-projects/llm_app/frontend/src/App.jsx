import { useState, useRef, useEffect, useMemo } from 'react'
import { marked } from 'marked'
import './App.css'

// Configure marked for safe rendering
marked.setOptions({
  breaks: true,  // Convert \n to <br>
  gfm: true,     // GitHub Flavored Markdown
})

function App() {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [file, setFile] = useState(null)
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState({ connected: false, modelLoaded: false })
  const messagesEndRef = useRef(null)
  const fileInputRef = useRef(null)

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
      const response = await fetch('/api/health')
      const data = await response.json()
      setStatus({ connected: true, modelLoaded: data.model_loaded })
    } catch (error) {
      setStatus({ connected: false, modelLoaded: false })
    }
  }

  const sendMessage = async (e) => {
    e.preventDefault()
    const messageText = input.trim()
    if ((!messageText && !file) || loading) return

    const userMessage = messageText
    const fileToSend = file
    const displayMessage = fileToSend
      ? (userMessage ? `${userMessage}\n\nAttached: ${fileToSend.name}` : `Attached: ${fileToSend.name}`)
      : userMessage

    setInput('')
    if (fileToSend) {
      setFile(null)
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
    setMessages(prev => [...prev, { role: 'user', content: displayMessage }])
    setLoading(true)

    try {
      let response
      if (fileToSend) {
        const formData = new FormData()
        formData.append('file', fileToSend)
        const url = userMessage
          ? `/api/chat?message=${encodeURIComponent(userMessage)}`
          : '/api/chat'
        response = await fetch(url, { method: 'POST', body: formData })
      } else {
        response = await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: userMessage })
        })
      }
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

  const handleFileChange = (e) => {
    const nextFile = e.target.files?.[0] || null
    setFile(nextFile)
  }

  const clearFile = () => {
    setFile(null)
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
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
              {msg.role === 'assistant' ? (
                <div
                  className="message-content markdown"
                  dangerouslySetInnerHTML={{ __html: marked.parse(msg.content || '') }}
                />
              ) : (
                <div className="message-content">{msg.content}</div>
              )}
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
          <div className="input-row">
            <label className="upload-button">
              <input
                ref={fileInputRef}
                type="file"
                accept=".pdf,.png,.jpg,.jpeg,.bmp,.tiff,.tif"
                onChange={handleFileChange}
                disabled={loading}
                className="file-input"
              />
              Upload
            </label>
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Type a message or upload a document..."
              disabled={loading}
            />
            <button type="submit" disabled={loading || (!input.trim() && !file)}>
              Send
            </button>
          </div>
          {file && (
            <div className="file-chip">
              <span className="file-name">{file.name}</span>
              <button type="button" className="file-remove" onClick={clearFile}>
                Remove
              </button>
            </div>
          )}
        </form>
      </main>
    </div>
  )
}

export default App
