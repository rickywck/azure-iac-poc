import { useState, useEffect } from 'react'
import { api } from '../api/client'
import './TasksTab.css'

export default function TasksTab() {
  const [tasks, setTasks] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [showForm, setShowForm] = useState(false)
  const [editingTask, setEditingTask] = useState(null)
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    status: 'pending'
  })

  useEffect(() => {
    loadTasks()
  }, [])

  const loadTasks = async () => {
    try {
      setLoading(true)
      const data = await api.getTasks()
      setTasks(data)
      setError(null)
    } catch (err) {
      setError('Failed to load tasks: ' + err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    try {
      if (editingTask) {
        await api.updateTask(editingTask.id, formData)
      } else {
        await api.createTask(formData)
      }
      setFormData({ title: '', description: '', status: 'pending' })
      setShowForm(false)
      setEditingTask(null)
      loadTasks()
    } catch (err) {
      setError('Failed to save task: ' + err.message)
    }
  }

  const handleEdit = (task) => {
    setEditingTask(task)
    setFormData({
      title: task.title,
      description: task.description || '',
      status: task.status
    })
    setShowForm(true)
  }

  const handleDelete = async (id) => {
    if (!confirm('Are you sure?')) return
    try {
      await api.deleteTask(id)
      loadTasks()
    } catch (err) {
      setError('Failed to delete task: ' + err.message)
    }
  }

  if (loading) return <div>Loading tasks...</div>

  return (
    <div className="tasks-tab">
      {error && <div className="error">{error}</div>}

      <div style={{ marginBottom: '15px' }}>
        <button onClick={() => { setShowForm(true); setEditingTask(null); setFormData({ title: '', description: '', status: 'pending' }) }}>
          + New Task
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleSubmit} className="task-form">
          <h3>{editingTask ? 'Edit Task' : 'New Task'}</h3>
          <input
            type="text"
            placeholder="Title"
            value={formData.title}
            onChange={(e) => setFormData({ ...formData, title: e.target.value })}
            required
          />
          <textarea
            placeholder="Description"
            value={formData.description}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            rows="3"
          />
          <select
            value={formData.status}
            onChange={(e) => setFormData({ ...formData, status: e.target.value })}
          >
            <option value="pending">Pending</option>
            <option value="active">Active</option>
            <option value="done">Done</option>
          </select>
          <div>
            <button type="submit">Save</button>
            <button type="button" onClick={() => { setShowForm(false); setEditingTask(null) }}>Cancel</button>
          </div>
        </form>
      )}

      <div className="tasks-list">
        {tasks.map(task => (
          <div key={task.id} className="task-item">
            <div className="task-header">
              <h4>{task.title}</h4>
              <span className={`status status-${task.status}`}>{task.status}</span>
            </div>
            {task.description && <p className="task-description">{task.description}</p>}
            <div className="task-actions">
              <button onClick={() => handleEdit(task)}>Edit</button>
              <button onClick={() => handleDelete(task.id)}>Delete</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
