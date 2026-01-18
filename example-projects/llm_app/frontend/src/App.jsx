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

// Strip <think>...</think> tags from content
function stripThinkingTags(content) {
  if (!content) return ''
  return content.replace(/<think>[\s\S]*?<\/think>/gi, '').trim()
}

// ThinkingSection component - foldable section showing AI thinking
function ThinkingSection({ thinking, isExpanded, onToggle }) {
  if (!thinking) return null

  const lines = thinking.split('\n')
  const previewLines = lines.slice(0, 2).join('\n')
  const hasMore = lines.length > 2 || (lines.length === 2 && lines[1].length > 100)

  return (
    <div className="thinking-section">
      <button
        className="thinking-toggle"
        onClick={onToggle}
        aria-expanded={isExpanded}
      >
        <span className="thinking-icon">{isExpanded ? '▼' : '▶'}</span>
        <span className="thinking-label">Thinking</span>
      </button>
      <div className={`thinking-content ${isExpanded ? 'expanded' : 'collapsed'}`}>
        {isExpanded ? thinking : (
          <>
            {previewLines}
            {hasMore && <span className="thinking-ellipsis">...</span>}
          </>
        )}
      </div>
    </div>
  )
}

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
  const [showTyping, setShowTyping] = useState(false)
  const [status, setStatus] = useState({ connected: false, modelLoaded: false })
  const [conversationId, setConversationId] = useState(null)
  const [expandedThinking, setExpandedThinking] = useState({})
  const messagesEndRef = useRef(null)
  const fileInputRef = useRef(null)
  const storeRef = useRef(emptyStore)
  const streamRef = useRef(null)
  const abortRef = useRef(null)

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

  useEffect(() => {
    return () => {
      if (streamRef.current) {
        streamRef.current.close()
        streamRef.current = null
      }
    }
  }, [])

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

  const updateMessageById = (convId, messageId, updater) => {
    setMessages(prev => {
      const next = prev.map(msg => (msg.id === messageId ? updater(msg) : msg))
      if (convId) {
        persistConversation(convId, next)
      }
      return next
    })
  }

  const stopStream = () => {
    if (streamRef.current) {
      streamRef.current.close()
      streamRef.current = null
    }
    if (abortRef.current) {
      abortRef.current.abort()
      abortRef.current = null
    }
    setLoading(false)
    setShowTyping(false)
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
    setShowTyping(true)
    let usedStreaming = false

    let activeConversation
    try {
      activeConversation = await ensureConversation()
    } catch (error) {
      setMessages(prev => [...prev, {
        role: 'error',
        content: error.message || 'Failed to start conversation'
      }])
      setLoading(false)
      setShowTyping(false)
      return
    }

    appendMessage(activeConversation, { role: 'user', content: displayMessage })

    try {
      let response
      if (fileToSend) {
        const controller = new AbortController()
        abortRef.current = controller
        const formData = new FormData()
        formData.append('file', fileToSend)
        const url = userMessage
          ? `/api/chat/${encodeURIComponent(activeConversation)}?message=${encodeURIComponent(userMessage)}`
          : `/api/chat/${encodeURIComponent(activeConversation)}`
        response = await fetch(url, { method: 'POST', body: formData, signal: controller.signal })
      } else {
        usedStreaming = true
        const assistantId = `assistant-${Date.now()}-${Math.random().toString(16).slice(2)}`

        const streamUrl = `/api/chat/${encodeURIComponent(activeConversation)}/stream?message=${encodeURIComponent(userMessage)}`
        const eventSource = new EventSource(streamUrl)
        streamRef.current = eventSource
        let hasMessage = false
        eventSource.onmessage = (event) => {
          let payload
          try {
            payload = JSON.parse(event.data)
          } catch (err) {
            return
          }

          if (payload.token) {
            if (!hasMessage) {
              hasMessage = true
              setShowTyping(false)
              appendMessage(activeConversation, {
                id: assistantId,
                role: 'assistant',
                content: payload.token,
                tokens: null
              })
              return
            }
            updateMessageById(activeConversation, assistantId, msg => ({
              ...msg,
              content: `${msg.content || ''}${payload.token}`
            }))
          }

          if (payload.error) {
            setShowTyping(false)
            if (hasMessage) {
              updateMessageById(activeConversation, assistantId, msg => ({
                ...msg,
                role: 'error',
                content: payload.error
              }))
            } else {
              appendMessage(activeConversation, { role: 'error', content: payload.error })
            }
            stopStream()
          }

          if (payload.done) {
            setShowTyping(false)
            if (hasMessage) {
              updateMessageById(activeConversation, assistantId, msg => ({
                ...msg,
                tokens: payload.tokens_used || null,
                thinking: payload.thinking || null
              }))
            }
            stopStream()
          }
        }

        eventSource.onerror = () => {
          setShowTyping(false)
          if (hasMessage) {
            updateMessageById(activeConversation, assistantId, msg => ({
              ...msg,
              role: msg.content ? 'assistant' : 'error',
              content: msg.content || 'Streaming connection closed.'
            }))
          } else {
            appendMessage(activeConversation, { role: 'error', content: 'Streaming connection closed.' })
          }
          stopStream()
        }

        return
      }
      const data = await response.json()

      setShowTyping(false)
      if (data.error) {
        appendMessage(activeConversation, { role: 'error', content: data.error })
      } else {
        appendMessage(activeConversation, {
          role: 'assistant',
          content: data.response,
          tokens: data.tokens_used,
          thinking: data.thinking || null
        })
      }
    } catch (error) {
      if (error?.name === 'AbortError') {
        return
      }
      setShowTyping(false)
      appendMessage(activeConversation, {
        role: 'error',
        content: 'Failed to connect to backend. Is the server running?'
      })
    } finally {
      if (!usedStreaming) {
        setLoading(false)
        setShowTyping(false)
      }
      if (abortRef.current) {
        abortRef.current = null
      }
    }
  }

  const handleNewConversation = async () => {
    if (loading) return
    stopStream()
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

  const toggleThinking = (messageIdx) => {
    setExpandedThinking(prev => ({
      ...prev,
      [messageIdx]: !prev[messageIdx]
    }))
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
              {msg.role === 'assistant' && msg.thinking && (
                <ThinkingSection
                  thinking={msg.thinking}
                  isExpanded={expandedThinking[idx] || false}
                  onToggle={() => toggleThinking(idx)}
                />
              )}
              {msg.role === 'assistant' ? (
                <div
                  className="message-content markdown"
                  dangerouslySetInnerHTML={{ __html: marked.parse(stripThinkingTags(msg.content)) }}
                />
              ) : (
                <div className="message-content">{msg.content}</div>
              )}
              {msg.tokens && (
                <div className="message-meta">{msg.tokens} tokens</div>
              )}
            </div>
          ))}
          {showTyping && (
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
            {loading ? (
              <button type="button" onClick={stopStream}>
                Stop
              </button>
            ) : (
              <button type="submit" disabled={!input.trim() && !file}>
                Send
              </button>
            )}
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
