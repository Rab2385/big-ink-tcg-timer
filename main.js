const {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  powerSaveBlocker,
  screen,
} = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');

// The port is part of the page origin, and localStorage (saved event and
// presets) is stored per origin. Changing it would hide existing saved data.
const PORT = 18581;
let server;
let mainWindow;

// The player screen window (timer for the players), its display, and the
// power save blocker that keeps that display awake while it is open.
let playerWindow = null;
let playerDisplayId = null;
let playerWindowed = false;
let sleepBlockerId = null;

// A second launch would try to bind the same port. Hand off to the running
// instance instead and bring its window to the front.
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });
}

if (app.isPackaged) {
  app.setPath('userData', path.join(path.dirname(process.execPath), 'user_data'));
}

function mimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();

  if (ext === '.html') return 'text/html';
  if (ext === '.js') return 'application/javascript';
  if (ext === '.css') return 'text/css';
  if (ext === '.json') return 'application/json';
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.svg') return 'image/svg+xml';
  if (ext === '.wasm') return 'application/wasm';
  if (ext === '.ico') return 'image/x-icon';

  return 'application/octet-stream';
}

function startLocalServer() {
  const webDir = path.join(__dirname, 'build', 'web');

  server = http.createServer((req, res) => {
    try {
      const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
      let requestedPath = decodeURIComponent(url.pathname);

      if (requestedPath === '/') {
        requestedPath = '/index.html';
      }

      let filePath = path.join(webDir, requestedPath);

      if (!filePath.startsWith(webDir)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
        filePath = path.join(webDir, 'index.html');
      }

      res.writeHead(200, {
        'Content-Type': mimeType(filePath),
        'Cache-Control': 'no-store',
      });

      fs.createReadStream(filePath).pipe(res);
    } catch (error) {
      res.writeHead(500);
      res.end('Server error');
    }
  });

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(PORT, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
}

function screenList() {
  const primaryId = screen.getPrimaryDisplay().id;
  return screen.getAllDisplays().map((display, index) => ({
    id: display.id,
    label: display.label || `Screen ${index + 1}`,
    width: display.size.width,
    height: display.size.height,
    primary: display.id === primaryId,
  }));
}

// Sent to the control window as JSON (see lib/display_bridge.dart).
function displayStatus() {
  return JSON.stringify({
    screens: screenList(),
    playerOpen: playerWindow !== null,
    playerScreenId: playerDisplayId,
    windowed: playerWindowed,
  });
}

function notifyDisplayChange() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('display:changed');
  }
}

function closePlayerWindow() {
  if (!playerWindow) return;
  const closing = playerWindow;
  playerWindow = null;
  playerDisplayId = null;
  playerWindowed = false;
  if (!closing.isDestroyed()) closing.destroy();
  if (sleepBlockerId !== null) {
    powerSaveBlocker.stop(sleepBlockerId);
    sleepBlockerId = null;
  }
}

// Opens the player screen full screen on the chosen display, or on the first
// display that is not the main one. Without a second display it opens as a
// normal window that can be dragged to a TV later.
function openPlayerWindow(displayId) {
  const displays = screen.getAllDisplays();
  const primaryId = screen.getPrimaryDisplay().id;
  const chosen =
    displays.find((display) => display.id === displayId) ||
    displays.find((display) => display.id !== primaryId) ||
    null;
  const windowed = chosen === null;

  if (playerWindow && !windowed && playerDisplayId === chosen.id) {
    playerWindow.focus();
    return;
  }
  closePlayerWindow();

  const bounds = windowed ? null : chosen.bounds;
  const win = new BrowserWindow({
    ...(windowed
      ? { width: 1280, height: 720 }
      : {
          x: bounds.x,
          y: bounds.y,
          width: bounds.width,
          height: bounds.height,
          frame: false,
        }),
    title: 'Big Ink TCG Timer – Player Screen',
    autoHideMenuBar: true,
    backgroundColor: '#06101F',
    show: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  playerWindow = win;
  playerDisplayId = windowed ? null : chosen.id;
  playerWindowed = windowed;
  sleepBlockerId = powerSaveBlocker.start('prevent-display-sleep');

  win.once('ready-to-show', () => {
    win.show();
    if (!windowed) {
      // Place the window on the TV first, then go full screen there. Asking
      // for full screen at creation can land on the main screen on Windows.
      win.setBounds(bounds);
      win.setFullScreen(true);
    }
  });
  if (!windowed) {
    // Nobody uses a mouse on the TV; hide the pointer there.
    win.webContents.on('did-finish-load', () => {
      win.webContents.insertCSS('* { cursor: none !important; }');
    });
  }
  win.on('closed', () => {
    if (playerWindow === win) {
      closePlayerWindow();
      notifyDisplayChange();
    }
  });

  // Matches playerViewQuery in lib/main.dart.
  win.loadURL(`http://127.0.0.1:${PORT}/?view=player`);
}

ipcMain.handle('display:status', () => displayStatus());
ipcMain.handle('display:open-player', (_event, displayId) => {
  openPlayerWindow(typeof displayId === 'number' ? displayId : null);
  return displayStatus();
});
ipcMain.handle('display:close-player', () => {
  closePlayerWindow();
  return displayStatus();
});

function watchDisplays() {
  screen.on('display-added', notifyDisplayChange);
  screen.on('display-metrics-changed', notifyDisplayChange);
  screen.on('display-removed', (_event, removed) => {
    // The TV was unplugged: close its window instead of letting Windows
    // move it on top of the control panel.
    if (removed.id === playerDisplayId) closePlayerWindow();
    notifyDisplayChange();
  });
}

async function createWindow() {
  try {
    await startLocalServer();
  } catch (error) {
    const reason =
      error && error.code === 'EADDRINUSE'
        ? `Port ${PORT} is already used by another program. Close that program (or restart the computer) and start Big Ink TCG Timer again.`
        : `The local web server could not start: ${error && error.message ? error.message : error}`;
    dialog.showErrorBox('Big Ink TCG Timer could not start', reason);
    app.quit();
    return;
  }

  const win = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 900,
    minHeight: 650,
    autoHideMenuBar: true,
    backgroundColor: '#06101F',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      // The end-of-round bell must play even right after a restart, before
      // anyone clicked, and on time while the window is in the background.
      autoplayPolicy: 'no-user-gesture-required',
      backgroundThrottling: false,
    },
  });

  mainWindow = win;
  win.on('closed', () => {
    mainWindow = null;
    closePlayerWindow();
  });
  watchDisplays();

  win.loadURL(`http://127.0.0.1:${PORT}`);
}

if (app.hasSingleInstanceLock()) {
  app.whenReady().then(createWindow);
}

app.on('window-all-closed', () => {
  if (server) server.close();

  if (process.platform !== 'darwin') {
    app.quit();
  }
});