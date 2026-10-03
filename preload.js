// Gives the control window a small, safe API for the player screen window.
// Used by lib/display_bridge.dart through window.bigInkDesktop.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('bigInkDesktop', {
  status: () => ipcRenderer.invoke('display:status'),
  openPlayer: (displayId) => ipcRenderer.invoke('display:open-player', displayId),
  closePlayer: () => ipcRenderer.invoke('display:close-player'),
  onChange: (callback) => {
    ipcRenderer.on('display:changed', () => callback());
  },
});
