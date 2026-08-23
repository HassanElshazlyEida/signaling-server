// Socket.IO signaling server for WebRTC voice calls.
//
// Same protocol as the original raw-WebSocket version: each connected
// client registers with a unique ID, and messages addressed to a target ID
// are relayed to that client. The only difference is the transport layer —
// Socket.IO negotiates a real WebSocket when the network/proxy allows it,
// and transparently falls back to HTTP long-polling when it doesn't (e.g.
// behind a reverse proxy that blocks the WebSocket Upgrade handshake).
// Everything above the transport (message shapes, ids, relay logic) is
// unchanged, so the rest of the app doesn't need to know which transport
// is actually in use.

const http = require('http');
const { Server } = require('socket.io');

const PORT = process.env.PORT || 8080;

const httpServer = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Signaling server is running.\n');
});

const io = new Server(httpServer, {
  // Must match the public URL prefix the app is served under (cPanel's
  // Node.js Selector maps https://<domain>/socket -> this app), otherwise
  // the client's Engine.IO handshake requests 404.
  path: '/socket/socket.io/',
  cors: { origin: '*' },
});

// id -> socket
const clients = new Map();

function send(socket, obj) {
  if (socket) socket.emit('signal', obj);
}

io.on('connection', (socket) => {
  let myId = null;

  socket.on('signal', (msg) => {
    if (!msg || typeof msg !== 'object') return;

    switch (msg.type) {
      case 'register': {
        myId = String(msg.id);
        clients.set(myId, socket);
        console.log(`registered: ${myId} (${clients.size} online)`);
        send(socket, { type: 'registered', id: myId });
        break;
      }

      // offer/answer/candidate/hangup all follow the same shape:
      // { type, target, from, ...payload }
      case 'offer':
      case 'answer':
      case 'candidate':
      case 'hangup': {
        const target = clients.get(String(msg.target));
        if (!target) {
          send(socket, { type: 'error', message: `user ${msg.target} not online` });
          return;
        }
        send(target, { ...msg, from: myId });
        break;
      }

      default:
        break;
    }
  });

  socket.on('disconnect', () => {
    if (myId) {
      clients.delete(myId);
      console.log(`disconnected: ${myId} (${clients.size} online)`);
    }
  });
});

httpServer.listen(PORT, () => {
  console.log(`Signaling server (Socket.IO) listening on port ${PORT}`);
});
