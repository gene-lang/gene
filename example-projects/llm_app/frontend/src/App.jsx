import { useState, useRef, useEffect } from 'react'
import { marked } from 'marked'
import './App.css'

// Configure marked for safe rendering
marked.setOptions({
  breaks: true,  // Convert \n to <br>
  gfm: true,     // GitHub Flavored Markdown
})

const STORAGE_KEY = 'gene_llm_conversations'

const emptyStore = { conversations: {}, lastConversationId: null }

const loadConversationStore = () => {
  if (typeof localStorage === 'undefined') return emptyStore
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return emptyStore
    const parsed = JSON.parse(raw)
    return {
      conversations: parsed.conversations || {},
      lastConversationId: parsed.lastConversationId || null,
    }
  } catch (error) {
    return emptyStore
  }
}

const saveConversationStore = (store) => {
  if (typeof localStorage === 'undefined') return
  localStorage.setItem(STORAGE_KEY, JSON.stringify(store))
}

function App() {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [file, setFile] = useState(null)
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState({ connected: false, modelLoaded: false })
  const [conversationId, setConversationId] = useState(null)
  const messagesEndRef = useRef(null)
  const fileInputRef = useRef(null)
  const storeRef = useRef(emptyStore)

  // Check backend health on mount
  useEffect(() => {
    checkHealth()
  }, [])

  useEffect(() => {
    const stored = loadConversationStore()
    storeRef.current = stored
    const lastId = stored.lastConversationId
    const lastConversation = lastId ? stored.conversations[lastId] : null
    if (lastConversation) {
      const history = Array.isArray(lastConversation.messages)
        ? lastConversation.messages
        : []
      setConversationId(lastId)
      setMessages(history)
    }
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

  const persistConversation = (convId, nextMessages) => {
    if (!convId) return
    const store = storeRef.current || emptyStore
    const existing = store.conversations[convId] || { id: convId, messages: [] }
    const nextStore = {
      ...store,
      conversations: {
        ...store.conversations,
        [convId]: { ...existing, id: convId, messages: nextMessages },
      },
      lastConversationId: convId,
    }
    storeRef.current = nextStore
    saveConversationStore(nextStore)
  }

  const setActiveConversation = (convId, nextMessages) => {
    setConversationId(convId)
    setMessages(nextMessages)
    persistConversation(convId, nextMessages)
  }

  const appendMessage = (convId, message) => {
    if (!convId) {
      setMessages(prev => [...prev, message])
      return
    }
    setMessages(prev => {
      const next = [...prev, message]
      persistConversation(convId, next)
      return next
    })
  }

  const createConversation = async (initialMessages = []) => {
    const response = await fetch('/api/chat/new', { method: 'POST' })
    const data = await response.json()
    if (!response.ok || data.error || !data.conversation_id) {
      throw new Error(data.error || 'Failed to start conversation')
    }
    setActiveConversation(data.conversation_id, initialMessages)
    return data.conversation_id
  }

  const ensureConversation = async () => {
    if (conversationId) return conversationId
    return createConversation(messages)
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
    setLoading(true)

    let activeConversation
    try {
      activeConversation = await ensureConversation()
    } catch (error) {
      setMessages(prev => [...prev, {
        role: 'error',
        content: error.message || 'Failed to start conversation'
      }])
      setLoading(false)
      return
    }

    appendMessage(activeConversation, { role: 'user', content: displayMessage })

    try {
      let response
      if (fileToSend) {
        const formData = new FormData()
        formData.append('file', fileToSend)
        const url = userMessage
          ? `/api/chat/${encodeURIComponent(activeConversation)}?message=${encodeURIComponent(userMessage)}`
          : `/api/chat/${encodeURIComponent(activeConversation)}`
        response = await fetch(url, { method: 'POST', body: formData })
      } else {
        response = await fetch(`/api/chat/${encodeURIComponent(activeConversation)}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: userMessage })
        })
      }
      const data = await response.json()

      if (data.error) {
        appendMessage(activeConversation, { role: 'error', content: data.error })
      } else {
        appendMessage(activeConversation, {
          role: 'assistant',
          content: data.response,
          tokens: data.tokens_used
        })
      }
    } catch (error) {
      appendMessage(activeConversation, {
        role: 'error',
        content: 'Failed to connect to backend. Is the server running?'
      })
    } finally {
      setLoading(false)
    }
  }

  const handleNewConversation = async () => {
    if (loading) return
    try {
      setInput('')
      setFile(null)
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
      await createConversation([])
    } catch (error) {
      setMessages(prev => [...prev, {
        role: 'error',
        content: error.message || 'Failed to start conversation'
      }])
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
        <div className="header-actions">
          <div className="status">
            <span className={`dot ${status.connected ? 'connected' : 'disconnected'}`}></span>
            {status.connected
              ? (status.modelLoaded ? 'LLM Ready' : 'Mock Mode')
              : 'Disconnected'}
          </div>
          <button
            type="button"
            className="new-conversation"
            onClick={handleNewConversation}
            disabled={loading}
          >
            New Conversation
          </button>
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
