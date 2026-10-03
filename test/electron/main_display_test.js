// Tests the player screen window logic in main.js with a fake Electron.
// Run with: npm run test:electron
const test = require('node:test');
const assert = require('node:assert');
const Module = require('node:module');
const path = require('node:path');
const { EventEmitter } = require('node:events');

function fakeElectron(displays) {
  const handlers = {};
  const windows = [];
  const screen = new EventEmitter();
  screen.getAllDisplays = () => displays;
  screen.getPrimaryDisplay = () => displays[0];

  class BrowserWindow extends EventEmitter {
    constructor(options) {
      super();
      this.options = options;
      this.destroyed = false;
      this.sent = [];
      this.webContents = {
        send: (channel) => this.sent.push(channel),
        on: () => {},
        insertCSS: () => {},
      };
      windows.push(this);
    }
    loadURL(url) {
      this.url = url;
      this.emit('ready-to-show');
    }
    show() {}
    setBounds(bounds) {
      this.bounds = bounds;
    }
    setFullScreen(value) {
      this.fullscreen = value;
    }
    isDestroyed() {
      return this.destroyed;
    }
    destroy() {
      this.destroyed = true;
      this.emit('closed');
    }
    focus() {}
  }

  const blockers = new Set();
  let nextBlocker = 1;

  return {
    handlers,
    windows,
    screen,
    blockers,
    electron: {
      app: {
        isPackaged: false,
        requestSingleInstanceLock: () => true,
        hasSingleInstanceLock: () => true,
        on: () => {},
        quit: () => {},
        whenReady: () => Promise.resolve(),
      },
      BrowserWindow,
      dialog: { showErrorBox: () => {} },
      ipcMain: { handle: (name, fn) => (handlers[name] = fn) },
      powerSaveBlocker: {
        start: () => {
          const id = nextBlocker++;
          blockers.add(id);
          return id;
        },
        stop: (id) => blockers.delete(id),
      },
      screen,
    },
  };
}

const laptop = {
  id: 1,
  label: 'Laptop',
  size: { width: 1920, height: 1080 },
  bounds: { x: 0, y: 0, width: 1920, height: 1080 },
};
const tv = {
  id: 2,
  label: 'LG TV',
  size: { width: 1920, height: 1080 },
  bounds: { x: 1920, y: 0, width: 1920, height: 1080 },
};

// Loads a fresh copy of main.js against the given displays.
async function loadMain(displays) {
  const fake = fakeElectron(displays);
  const originalLoad = Module._load;
  // A fake web server, so tests neither need nor block port 18581.
  const http = {
    createServer: () => {
      const server = new EventEmitter();
      server.listen = (_port, _host, ready) => setImmediate(ready);
      server.close = () => {};
      return server;
    },
  };
  Module._load = function (request, ...rest) {
    if (request === 'electron') return fake.electron;
    if (request === 'http') return http;
    return originalLoad.call(this, request, ...rest);
  };
  const mainPath = path.join(__dirname, '..', '..', 'main.js');
  delete require.cache[require.resolve(mainPath)];
  try {
    require(mainPath);
  } finally {
    Module._load = originalLoad;
  }
  // Let createWindow() start the server and open the control window.
  await new Promise((resolve) => setTimeout(resolve, 100));
  return fake;
}

async function status(fake) {
  return JSON.parse(await fake.handlers['display:status']());
}

test('opens full screen on the second display by default', async () => {
  const fake = await loadMain([laptop, tv]);
  const result = JSON.parse(await fake.handlers['display:open-player']({}));

  assert.equal(result.playerOpen, true);
  assert.equal(result.playerScreenId, tv.id);
  assert.equal(result.windowed, false);

  const player = fake.windows.at(-1);
  assert.equal(player.options.x, tv.bounds.x);
  assert.deepEqual(player.bounds, tv.bounds);
  assert.equal(player.fullscreen, true);
  assert.equal(player.options.frame, false);
  assert.match(player.url, /\?view=player$/);
  assert.equal(fake.blockers.size, 1, 'keeps the display awake');

  await fake.handlers['display:close-player']();
  assert.equal(fake.blockers.size, 0);
});

test('opens a normal window when there is only one display', async () => {
  const fake = await loadMain([laptop]);
  const result = JSON.parse(await fake.handlers['display:open-player']({}));

  assert.equal(result.playerOpen, true);
  assert.equal(result.windowed, true);
  assert.equal(fake.windows.at(-1).fullscreen, undefined);
  await fake.handlers['display:close-player']();
});

test('the chosen display wins, even the main one', async () => {
  const fake = await loadMain([laptop, tv]);
  const result = JSON.parse(
    await fake.handlers['display:open-player']({}, laptop.id),
  );
  assert.equal(result.playerScreenId, laptop.id);
  assert.equal(fake.windows.at(-1).options.x, laptop.bounds.x);
  await fake.handlers['display:close-player']();
});

test('unplugging the TV closes the player window and tells the app', async () => {
  const fake = await loadMain([laptop, tv]);
  await fake.handlers['display:open-player']({});
  const control = fake.windows[0];

  fake.screen.emit('display-removed', {}, tv);

  assert.equal((await status(fake)).playerOpen, false);
  assert.equal(fake.blockers.size, 0);
  assert.ok(control.sent.includes('display:changed'));
});

test('closing the control window also closes the player window', async () => {
  const fake = await loadMain([laptop, tv]);
  await fake.handlers['display:open-player']({});
  const player = fake.windows.at(-1);

  fake.windows[0].emit('closed');
  assert.equal(player.destroyed, true);
  assert.equal(fake.blockers.size, 0);
});
