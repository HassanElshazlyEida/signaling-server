// Minimal WebSocket signaling server for WebRTC voice calls.
// Each connected client registers with a unique ID. Messages addressed
// to a target ID are simply relayed to that client's socket.

const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocket.Server({ port: PORT });

// id -> ws
const clients = new Map();

function send(ws, obj) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

wss.on('connection', (ws) => {
  let myId = null;

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (e) {
      return; // ignore malformed messages
    }

    switch (msg.type) {
      case 'register': {
        myId = String(msg.id);
        clients.set(myId, ws);
        console.log(`registered: ${myId} (${clients.size} online)`);
        send(ws, { type: 'registered', id: myId });
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
          send(ws, { type: 'error', message: `user ${msg.target} not online` });
          return;
        }
        send(target, { ...msg, from: myId });
        break;
      }

      default:
        break;
    }
  });

  ws.on('close', () => {
    if (myId) {
      clients.delete(myId);
      console.log(`disconnected: ${myId} (${clients.size} online)`);
    }
  });
});

console.log(`Signaling server listening on ws://0.0.0.0:${PORT}`);
