#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "=========================================================="
echo "[START] Khởi tạo Web EC2 (Case 3) lúc: $(date -u)"
echo "=========================================================="


DB_PRIVATE_IP="THAY_PRIVATE_IP_DB_EC2_VAO_DAY"

DB_NAME="cloudevo_db"
DB_USER="cloudevo"
DB_PASS="CloudEvo@2026"
DB_PORT="5432"

# 1. Cài đặt Docker & Docker Compose plugin
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg postgresql-client
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# 2. Tạo cấu trúc thư mục ứng dụng CloudEvo
mkdir -p /opt/cloudevo/app/src
cd /opt/cloudevo

# 3. Tạo package.json
cat << 'EOF' > /opt/cloudevo/app/package.json
{
  "name": "cloudevo-tracker",
  "version": "1.0.0",
  "main": "src/server.js",
  "dependencies": {
    "express": "^4.19.2",
    "pg": "^8.11.5"
  }
}
EOF

# 4. Tạo mã nguồn Web App (server.js) trả HTTP 503 ở /health khi DB mất kết nối
cat << 'EOF' > /opt/cloudevo/app/src/server.js
const express = require('express');
const os = require('os');
const { Pool } = require('pg');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const PORT = process.env.PORT || 3000;
const STORAGE_MODE = process.env.STORAGE_MODE || 'postgres';
const DB_HOST = process.env.DB_HOST || 'localhost';

const pool = new Pool({
  host: DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER || 'cloudevo',
  password: process.env.DB_PASSWORD || 'CloudEvo@2026',
  database: process.env.DB_NAME || 'cloudevo_db',
  connectionTimeoutMillis: 2000,
  query_timeout: 2000
});

// Endpoint /health phục vụ dr_monitor.py đo RTO chính xác cho cả Web và DB
app.get('/health', async (req, res) => {
  const start = Date.now();
  let dbConnected = false;
  let latency = 0;

  try {
    await pool.query('SELECT 1');
    dbConnected = true;
    latency = Date.now() - start;
  } catch (err) {
    dbConnected = false;
    latency = Date.now() - start;
  }

  const statusCode = dbConnected ? 200 : 503;
  res.status(statusCode).json({
    status: dbConnected ? 'UP' : 'DOWN',
    mode: STORAGE_MODE,
    db_connected: dbConnected,
    db_host: DB_HOST,
    db_latency_ms: latency,
    hostname: os.hostname(),
    server_time: new Date().toISOString()
  });
});

app.post('/api/transactions', async (req, res) => {
  const { customer, amount } = req.body;
  try {
    await pool.query(
      'INSERT INTO transactions (customer, amount) VALUES ($1, $2)',
      [customer || 'Walk-in Customer', parseFloat(amount || 100)]
    );
    res.redirect('/');
  } catch (err) {
    res.status(500).send('Database Error: ' + err.message);
  }
});

app.get('/', async (req, res) => {
  let rows = [];
  let dbOk = false;
  let latency = 0;
  const start = Date.now();
  try {
    const result = await pool.query('SELECT id, customer, amount, created_at FROM transactions ORDER BY id DESC LIMIT 10');
    rows = result.rows;
    dbOk = true;
    latency = Date.now() - start;
  } catch (e) {
    dbOk = false;
  }

  const rowsHtml = rows.map(r => `
    <tr>
      <td>#${r.id}</td>
      <td>${r.customer}</td>
      <td>$${Number(r.amount).toFixed(2)}</td>
      <td>${new Date(r.created_at).toISOString()}</td>
    </tr>
  `).join('');

  res.send(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>CloudEvo Order & Transaction Tracker</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f4f6f8; margin: 0; padding: 40px; }
    .card { max-width: 820px; margin: 0 auto; background: #fff; padding: 32px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    h1 { margin-top: 0; color: #111827; }
    .subtitle { color: #4b5563; margin-bottom: 12px; font-weight: 500; }
    .badge { display: inline-block; padding: 6px 14px; border-radius: 6px; font-weight: 600; font-size: 13px; color: #fff; background: ${dbOk ? '#2563eb' : '#dc2626'}; margin-bottom: 24px; }
    .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
    .box { background: #f9fafb; border: 1px solid #e5e7eb; padding: 14px; border-radius: 8px; }
    .box-label { font-size: 12px; color: #6b7280; font-weight: 600; }
    .box-val { font-size: 14px; color: #111827; margin-top: 4px; font-family: monospace; }
    form { display: flex; gap: 12px; margin-bottom: 28px; }
    input { padding: 10px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; }
    input[name="customer"] { flex: 1; }
    input[name="amount"] { width: 120px; }
    button { background: #111827; color: #fff; border: none; padding: 10px 18px; border-radius: 6px; font-weight: 600; cursor: pointer; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 12px; border-bottom: 1px solid #e5e7eb; font-size: 14px; }
    th { color: #4b5563; font-weight: 600; }
  </style>
</head>
<body>
  <div class="card">
    <h1>CloudEvo Order & Transaction Tracker</h1>
    <div class="subtitle">Active Architecture: Case 3 - Hosting 1 Web on EC2 + 1 DB on Single EC2 (Decoupled 2-Tier)</div>
    <div class="badge">STORAGE MODE: POSTGRES — ${dbOk ? `CONNECTED TO PRIVATE DB (${DB_HOST} \vert{}${latency}ms)` : 'DB DISCONNECTED'}</div>
    <div class="grid">
      <div class="box"><div class="box-label">Web Container / Hostname</div><div class="box-val">${os.hostname()}</div></div>
      <div class="box"><div class="box-label">Server Time (UTC)</div><div class="box-val">${new Date().toISOString()}</div></div>
      <div class="box"><div class="box-label">Health Endpoint</div><div class="box-val"><a href="/health">/health (JSON Check)</a></div></div>
    </div>
    <form method="POST" action="/api/transactions">
      <input type="text" name="customer" placeholder="Customer / Transaction Note" required />
      <input type="number" step="0.01" name="amount" value="250.00" required />
      <button type="submit">+ Record Transaction</button>
    </form>
    <h3>Recent Transactions (Latest 10)</h3>
    <table>
      <thead><tr><th>ID</th><th>Customer</th><th>Amount</th><th>Timestamp</th></tr></thead>
      <tbody>${rowsHtml || '<tr><td colspan="4">No transactions or Database unreachable</td></tr>'}</tbody>
    </table>
  </div>
</body>
</html>`);
});

app.listen(PORT, () => console.log('CloudEvo Web listening on port ' + PORT));
EOF

# 5. Tạo Dockerfile Multi-stage
cat << 'EOF' > /opt/cloudevo/app/Dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY src ./src
EXPOSE 3000
CMD ["node", "src/server.js"]
EOF

# 6. Tạo cấu hình Nginx Reverse Proxy
cat << 'EOF' > /opt/cloudevo/nginx.conf
events { worker_connections 1024; }
http {
    server {
        listen 80;
        location / {
            proxy_pass http://cloudevo-web:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

# 7. Tạo docker-compose.yml (Chỉ gồm Nginx + Web App, kết nối tới DB EC2 riêng)
cat << EOF > /opt/cloudevo/docker-compose.yml
services:
  cloudevo-web:
    build: ./app
    container_name: cloudevo-web
    restart: always
    environment:
      - PORT=3000
      - STORAGE_MODE=postgres
      - DB_HOST=${DB_PRIVATE_IP}
      - DB_PORT=${DB_PORT}
      - DB_USER=${DB_USER}
      - DB_PASSWORD=${DB_PASS}
      - DB_NAME=${DB_NAME}

  cloudevo-nginx:
    image: nginx:alpine
    container_name: cloudevo-nginx
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - cloudevo-web
EOF

# 8. Khởi chạy cụm container tầng Web
docker compose up -d --build

echo "=========================================================="
echo "[DONE] Hoàn tất cài đặt Web EC2 (Case 3) lúc: $(date -u)"
echo "=========================================================="