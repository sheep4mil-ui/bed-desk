const { app, BrowserWindow, desktopCapturer, session } = require('electron');

const bedDeskUrl = process.env.BED_DESK_URL;
if (!bedDeskUrl) throw new Error('BED_DESK_URL is required.');
const trustedOrigin = 'https://sheep4mil-ui.github.io';
if (!bedDeskUrl.startsWith(`${trustedOrigin}/bed-desk/`)) throw new Error('Untrusted Bed Desk URL.');

app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

app.whenReady().then(() => {
  session.defaultSession.setPermissionCheckHandler((webContents, permission) =>
    Boolean(webContents?.getURL().startsWith(`${trustedOrigin}/bed-desk/`)) &&
    (permission === 'media' || permission === 'display-capture')
  );
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) =>
    callback(Boolean(webContents?.getURL().startsWith(`${trustedOrigin}/bed-desk/`)) &&
      (permission === 'media' || permission === 'display-capture'))
  );
  session.defaultSession.setDisplayMediaRequestHandler(async (request, callback) => {
    if (!request.securityOrigin.startsWith(trustedOrigin)) return callback({});
    try {
      const sources = await desktopCapturer.getSources({
        types: ['screen'],
        thumbnailSize: { width: 0, height: 0 }
      });
      callback({ video: sources[0], audio: 'loopback' });
    } catch {
      callback({});
    }
  }, { useSystemPicker: false });

  const window = new BrowserWindow({
    width: 440,
    height: 660,
    minWidth: 380,
    minHeight: 520,
    autoHideMenuBar: true,
    backgroundColor: '#11110f',
    title: 'Bed Desk Streamer',
    webPreferences: { contextIsolation: true, nodeIntegration: false }
  });
  window.webContents.once('did-finish-load', () => {
    window.webContents.executeJavaScript(
      "document.getElementById('enablePcSound')?.click()",
      true
    ).catch(() => {});
  });
  window.loadURL(bedDeskUrl);
  window.on('closed', () => app.quit());
});

app.on('window-all-closed', () => app.quit());
