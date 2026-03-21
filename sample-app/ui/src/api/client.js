const API_BASE = '/api';

export const api = {
  // Tasks CRUD
  getTasks: async () => {
    const response = await fetch(`${API_BASE}/tasks`);
    if (!response.ok) throw new Error('Failed to fetch tasks');
    return response.json();
  },

  getTask: async (id) => {
    const response = await fetch(`${API_BASE}/tasks/${id}`);
    if (!response.ok) throw new Error('Failed to fetch task');
    return response.json();
  },

  createTask: async (task) => {
    const response = await fetch(`${API_BASE}/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task)
    });
    if (!response.ok) throw new Error('Failed to create task');
    return response.json();
  },

  updateTask: async (id, task) => {
    const response = await fetch(`${API_BASE}/tasks/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task)
    });
    if (!response.ok) throw new Error('Failed to update task');
    return response.json();
  },

  deleteTask: async (id) => {
    const response = await fetch(`${API_BASE}/tasks/${id}`, {
      method: 'DELETE'
    });
    if (!response.ok) throw new Error('Failed to delete task');
    return response.json();
  },

  // Agent chat
  sendChatMessage: async (message) => {
    const response = await fetch(`${API_BASE}/agent/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message })
    });
    if (!response.ok) throw new Error('Failed to send message');
    return response.json();
  }
};
