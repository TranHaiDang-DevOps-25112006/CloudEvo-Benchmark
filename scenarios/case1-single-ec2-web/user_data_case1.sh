#!/bin/bash
set -e

# Ghi toàn bộ log quá trình chạy User Data ra file /var/log/user-data.log để dễ kiểm tra
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "=== [CloudEvo Case 1] Bắt đầu khởi tạo tự động lúc $(date -Iseconds) ==="

# 1. Cài đặt Docker & Docker Compose
apt-get update -y
apt-get install -y docker.io docker-compose-v2 curl
systemctl enable --now docker

# 2. Tạo cấu trúc thư mục dự án trên EC2
mkdir -p /opt/cloudevo/app/src
mkdir -p /opt/cloudevo/scenarios/case1-single-ec2-web

# 3. Tạo package.json
cat << 'EOF' > /opt/cloudevo/app/package.json
{
  "name": "cloudevo-order-tracker",
  "version": "1.0.0",
  "main": "src/server.js",
  "dependencies": {
    "express": "^4.19.2",
    "pg": "^8.11.5"
  }
}
EOF

# 4. Tạo src/server.js
cat << 'EOF' > /opt/cloudevo/app/src/server.js
const express = require('express');
const os = require('os');
const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const PORT = process.env.PORT || 3000;
const STORAGE_MODE = process.env.STORAGE_MODE || 'memory';
const SCENARIO_NAME = process.env.SCENARIO_NAME || 'Case 1: Single EC2 (Automated User Data)';

const memoryTransactions = [
  { id: 1, customer: 'Automated Boot via EC2 User Data', amount: 199.00, created_at: new Date().toISOString() }
];

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'UP',
    mode: STORAGE_MODE,
    db_connected: false,
    db_latency_ms: 0,
    hostname: os.hostname(),
    server_time: new Date().toISOString()
  });
});

app.get('/api/transactions', (req, res) => {
  res.json({ mode: 'memory', count: memoryTransactions.length, data: memoryTransactions.slice(-20).reverse() });
});

app.post('/api/transactions', (req, res) => {
  const newTx = {
    id: memoryTransactions.length + 1,
    customer: req.body.customer || 'Test User',
    amount: parseFloat(req.body.amount || '50.00'),
    created_at: new Date().toISOString()
  };
  memoryTransactions.push(newTx);
  if (req.headers.accept && req.headers.accept.includes('text/html')) return res.redirect('/');
  res.status(201).json(newTx);
});

app.get('/', (req, res) => {
  const rowsHtml = [...memoryTransactions].reverse().slice(0, 10).map(t => `
    <tr>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;">#${t.id}</td>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;">${t.customer}</td>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;font-weight:bold;color:#059669;">$${Number(t.amount).toFixed(2)}</td>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;color:#6b7280;">${t.created_at}</td>
    </tr>
  `).join('');

  res.send(`
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"><title>CloudEvo Case 1</title></head>
    <body style="font-family:sans-serif;background:#f3f4f6;padding:24px;">
      <div style="max-width:850px;margin:0 auto;background:#fff;padding:24px;border-radius:12px;">
        <h1>CloudEvo Order & Transaction Tracker</h1>
        <p><strong>Active Architecture:</strong> ${SCENARIO_NAME}</p>
        <p><span style="background:#2563eb;color:#fff;padding:6px 12px;border-radius:6px;">Storage Mode: ${STORAGE_MODE.toUpperCase()} (Stateless)</span></p>
        <p><strong>Hostname:</strong> ${os.hostname()} | <strong>Server Time:</strong> ${new Date().toISOString()} | <a href="/health">/health</a></p>
        <form method="POST" action="/api/transactions" style="display:flex;gap:10px;margin:16px 0;">
          <input type="text" name="customer" placeholder="Customer Name" required style="flex:1;padding:8px;" />
          <input type="number" step="0.01" name="amount" value="100.00" required style="width:120px;padding:8px;" />
          <button type="submit" style="padding:8px 16px;background:#111827;color:#fff;border:none;border-radius:6px;">+ Add</button>
        </form>
        <table style="width:100%;border-collapse:collapse;">
          <thead><tr style="background:#f9fafb;"><th style="padding:10px;text-align:left;">ID</th><th style="padding:10px;text-align:left;">Customer</th><th style="padding:10px;text-align:left;">Amount</th><th style="padding:10px;text-align:left;">Timestamp</th></tr></thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>
    </body>
    </html>
  `);
});

app.listen(PORT, '0.0.0.0', () => console.log('Server started on port ' + PORT));
EOF

# 5. Tạo Dockerfile
cat << 'EOF' > /opt/cloudevo/app/Dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
EXPOSE 3000
CMD ["node", "src/server.js"]
EOF

# 6. Tạo nginx.conf
cat << 'EOF' > /opt/cloudevo/app/nginx.conf
events { worker_connections 1024; }
http {
    upstream cloudevo_backend { server web-app:3000; }
    server {
        listen 80;
        location / {
            proxy_pass http://cloudevo_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

# 7. Tạo docker-compose.yml và khởi chạy
cat << 'EOF' > /opt/cloudevo/scenarios/case1-single-ec2-web/docker-compose.yml
services:
  web-app:
    build: ../../app
    container_name: cloudevo-web
    restart: always
    environment:
      - PORT=3000
      - STORAGE_MODE=memory
      - SCENARIO_NAME=Case 1 - Single EC2 (Automated via User Data)
    expose:
      - "3000"
  nginx:
    image: nginx:1.25-alpine
    container_name: cloudevo-nginx
    restart: always
    ports:
      - "80:80"
    volumes:
      - ../../app/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - web-app
EOF

cd /opt/cloudevo/scenarios/case1-single-ec2-web
docker compose up -d --build
echo "=== [CloudEvo Case 1] Hoàn tất khởi chạy lúc $(date -Iseconds) ==="