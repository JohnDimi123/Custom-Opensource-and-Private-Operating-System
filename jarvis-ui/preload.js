// jarvis-ui/preload.js — secure bridge between renderer and main.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('jarvis', {
  quit: () => ipcRenderer.invoke('app:quit'),
  coreUrl: () => 'ws://127.0.0.1:8765',
});
