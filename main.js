const { app, BrowserWindow } = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 18581;
let server;

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

      if (!fs.existsSync(filePath)) {
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

  return new Promise((resolve) => {
    server.listen(PORT, '127.0.0.1', resolve);
  });
}

async function createWindow() {
  await startLocalServer();

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
    },
  });

  win.loadURL(`http://127.0.0.1:${PORT}`);
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (server) server.close();

  if (process.platform !== 'darwin') {
    app.quit();
  }
});