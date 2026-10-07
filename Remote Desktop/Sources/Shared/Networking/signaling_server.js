const http = require('http');
const WebSocket = require('ws');

/**
 * Minimal, stateless Node.js signaling server reference implementation for Remote Desktop.
 * Relays offers, answers, and ICE candidates between peers without persistent database or media access.
 */
const PORT = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Remote Desktop Signaling Server Online\n');
});

const wss = new WebSocket.Server({ server });
const clients = new Map(); // deviceID -> ws

wss.on('connection', (ws, req) => {
  const deviceID = req.headers['x-device-id'] || req.url.split('?id=')[1];

  if (!deviceID) {
    ws.close(1008, 'Device ID required');
    return;
  }

  clients.set(deviceID, ws);
  console.log(`[Signaling] Device connected: ${deviceID} (Total online: ${clients.size})`);

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      const targetID = msg.targetID;

      if (targetID && clients.has(targetID)) {
        const targetWs = clients.get(targetID);
        if (targetWs.readyState === WebSocket.OPEN) {
          targetWs.send(data);
        }
      }
    } catch (err) {
      console.error('[Signaling] Message parse error:', err);
    }
  });

  ws.on('close', () => {
    clients.delete(deviceID);
    console.log(`[Signaling] Device disconnected: ${deviceID}`);
  });
});

server.listen(PORT, () => {
  console.log(`[Signaling] Server listening on port ${PORT}`);
});
