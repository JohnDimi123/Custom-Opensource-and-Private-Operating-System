// jarvis-ui/main.js — Electron main process. Fullscreen frameless kiosk HUD.
const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');

app.disableHardwareAcceleration(); // safer inside VMs without GPU accel

let win;
function createWindow() {
  win = new BrowserWindow({
    fullscreen: true,
    frame: false,
    kiosk: true,
    backgroundColor: '#000308',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.on('closed', () => { win = null; });

  // Esc is intercepted in renderer; block accelerator quit in kiosk.
  win.webContents.on('before-input-event', (event, input) => {
    if (input.key === 'F12' && input.control && input.shift) {
      win.webContents.toggleDevTools();
    }
  });
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { /* stay alive; OS shell */ });

ipcMain.handle('app:quit', () => app.quit());
