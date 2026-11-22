const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = 8080;
const WEB_DIR = path.join(__dirname, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.css': 'text/css; charset=UTF-8',
  '.json': 'application/json; charset=UTF-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2'
};

const server = http.createServer((req, res) => {
  // Normalize URL
  let reqPath = req.url.split('?')[0];

  // Route for 3d html if requested
  if (reqPath === '/3d' || reqPath === '/supermarket_3d.html') {
    const filePath = path.join(__dirname, 'supermarket_3d.html');
    if (fs.existsSync(filePath)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=UTF-8' });
      return fs.createReadStream(filePath).pipe(res);
    }
  }

  if (reqPath === '/three.min.js') {
    const filePath = path.join(__dirname, 'three.min.js');
    if (fs.existsSync(filePath)) {
      res.writeHead(200, { 'Content-Type': 'application/javascript; charset=UTF-8' });
      return fs.createReadStream(filePath).pipe(res);
    }
  }

  // Serve from build/web
  let filePath = path.join(WEB_DIR, reqPath === '/' ? 'index.html' : reqPath);

  // Security check
  if (!filePath.startsWith(WEB_DIR)) {
    res.writeHead(403);
    return res.end('Access denied');
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Fallback to index.html for SPA
      filePath = path.join(WEB_DIR, 'index.html');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, {
      'Content-Type': contentType,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    });
    fs.createReadStream(filePath).pipe(res);
  });
});

const is3DMode = process.argv.includes('--3d');
const targetPath = is3DMode ? '/3d' : '';
const targetUrl = `http://127.0.0.1:${PORT}${targetPath}`;

function openBrowser(url) {
  const startCmd = process.platform === 'win32' ? `start "" "${url}"` : `open "${url}"`;
  exec(startCmd, (err) => {
    if (err) console.error('Tarayıcı açılamadı:', err);
    else console.log('🚀 Tarayıcı başarıyla açıldı:', url);
  });
}

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.log(`ℹ️ Sunucu zaten çalışıyor (${PORT}). Tarayıcı açılıyor: ${targetUrl}`);
    openBrowser(targetUrl);
    setTimeout(() => process.exit(0), 1000);
  } else {
    console.error('Sunucu hatası:', err);
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`✅ Süpermarket Simülatörü sunucusu aktif: ${targetUrl}`);
  openBrowser(targetUrl);
});
