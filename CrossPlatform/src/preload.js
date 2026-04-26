const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('commandNest', {
  getSettings: () => ipcRenderer.invoke('settings:get'),
  saveSettings: (settings) => ipcRenderer.invoke('settings:save', settings),
  refreshModels: () => ipcRenderer.invoke('models:refresh'),
  sendPrompt: (payload) => ipcRenderer.invoke('assistant:send', payload),
  closeWindow: () => ipcRenderer.invoke('window:close'),
  copyText: (text) => ipcRenderer.invoke('clipboard:copy', text),
  onNavigate: (callback) => ipcRenderer.on('app:navigate', (_, route) => callback(route)),
  onSettingsUpdated: (callback) => ipcRenderer.on('settings:updated', (_, settings) => callback(settings)),
  onAssistantChunk: (callback) => ipcRenderer.on('assistant:chunk', (_, payload) => callback(payload)),
  onAssistantDone: (callback) => ipcRenderer.on('assistant:done', (_, payload) => callback(payload)),
  onAssistantError: (callback) => ipcRenderer.on('assistant:error', (_, payload) => callback(payload)),
  onAssistantActivity: (callback) => ipcRenderer.on('assistant:activity', (_, payload) => callback(payload))
});
