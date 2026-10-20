#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== [CASE 4] STARTING WEB EC2 SETUP (CONNECTED TO AMAZON RDS) ==="

# ===== THAY ENDPOINT RDS THỰC TẾ VÀO DÒNG DƯỚI ĐÂY KHI DÁN VÀO EC2 USER DATA =====
RDS_ENDPOINT="YOUR_RDS_ENDPOINT_HERE"
DB_PORT="5432"
DB_NAME="cloudevo_db"
DB_USER="cloudevo"
DB_PASS="CloudEvoPass2026!"

# 1. Cài đặt Docker & Docker Compose
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release postgresql-client
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# 2. Tạo thư mục ứng dụng
mkdir -p /opt/cloudevo/app/src
cd /opt/cloudevo

# 3. Tạo package.json
cat << 'EOF' > /opt/cloudevo/app/package.json
{
  "name": "cloudevo-tracker",
  "version": "1.0.0",
  "main": "src/server.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.3"
  }
}
EOF

# 4. Tạo mã nguồn ứng dụng src/server.js (Hỗ trợ tự động Reconnect khi RDS Failover)
cat << 'EOF' > /opt/cloudevo/app/src/server.js
const express = require('express');
const { Pool } = require('pg');
const os = require('os');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const PORT = process.env.PORT || 3000;
const STORAGE_MODE = process.env.STORAGE_MODE || 'postgres';
const DB_HOST = process.env.DB_HOST || 'localhost';

const pool = new Pool({
  host: DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'cloudevo_db',
  user: process.env.DB_USER || 'cloudevo',
  password: process.env.DB_PASS || 'CloudEvoPass2026!',
  ssl: { rejectUnauthorized: false },
  max: 10,
  connectionTimeoutMillis: 2000,
  idleTimeoutMillis: 5000,
  query_timeout: 2000
});

// Tự động khởi tạo bảng transactions trên RDS
async function initDB() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS transactions (
        id SERIAL PRIMARY KEY,
        customer VARCHAR(255) NOT NULL,
        amount NUMERIC(10, 2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    const countRes = await pool.query('SELECT COUNT(*) FROM transactions');
    if (parseInt(countRes.rows[0].count) === 0) {
      await pool.query(
        'INSERT INTO transactions (customer, amount) VALUES ($1, $2)',
        ['Case 4 Initial Seed (Amazon RDS Multi-AZ)', 800.00]
      );
    }
    console.log("Connected to Amazon RDS & initialized table successfully.");
  } catch (err) {
    console.error("RDS initialization pending/retrying:", err.message);
  }
}
initDB();

// Health Check Endpoint (Trả HTTP 200 khi RDS sống, HTTP 503 khi RDS đang Failover)
app.get('/health', async (req, res) => {
  const start = Date.now();
  try {
    await pool.query('SELECT 1');
    const latency = Date.now() - start;
    return res.status(200).json({
      status: 'UP',
      mode: STORAGE_MODE,
      db_connected: true,
      db_host: DB_HOST,
      db_latency_ms: latency,
      hostname: os.hostname(),
      server_time: new Date().toISOString()
    });
  } catch (err) {
    return res.status(503).json({
      status: 'DOWN',
      mode: STORAGE_MODE,
      db_connected: false,
      db_host: DB_HOST,
      error: err.message,
      hostname: os.hostname(),
      server_time: new Date().toISOString()
    });
  }
});

// API thêm giao dịch mới
app.post('/api/transactions', async (req, res) => {
  const customer = req.body.customer || 'Anonymous Transaction';
  const amount = parseFloat(req.body.amount || 100);
  try {
    await initDB();
    await pool.query(
      'INSERT INTO transactions (customer, amount) VALUES ($1, $2)',
      [customer, amount]
    );
    res.redirect('/');
  } catch (err) {
    res.status(503).send('Database temporarily unavailable during Failover: ' + err.message);
  }
});

// Giao diện chính
app.get('/', async (req, res) => {
  const start = Date.now();
  let rows = [];
  let dbConnected = false;
  let latency = 0;

  try {
    const result = await pool.query('SELECT * FROM transactions ORDER BY id DESC LIMIT 10');
    rows = result.rows;
    dbConnected = true;
    latency = Date.now() - start;
  } catch (e) {
    dbConnected = false;
  }

  const badgeHtml = dbConnected
    ? `<div style="display:inline-block;background:#2563eb;color:#fff;padding:6px 14px;border-radius:6px;font-weight:700;font-size:13px;margin-bottom:20px;">
         STORAGE MODE: POSTGRES — CONNECTED TO AMAZON RDS (${DB_HOST} @ ${latency}ms)
       </div>`
    : `<div style="display:inline-block;background:#dc2626;color:#fff;padding:6px 14px;border-radius:6px;font-weight:700;font-size:13px;margin-bottom:20px;">
         STORAGE MODE: POSTGRES — RDS FAILOVER IN PROGRESS (DISCONNECTED)
       </div>`;

  const rowsHtml = rows.map(r => `
    <tr style="border-bottom:1px solid #f1f5f9;">
      <td style="padding:12px;color:#475569;font-weight:600;">#${r.id}</td>
      <td style="padding:12px;color:#1e293b;">${r.customer}</td>
      <td style="padding:12px;color:#0f172a;font-weight:700;">$${Number(r.amount).toFixed(2)}</td>
      <td style="padding:12px;color:#64748b;font-size:13px;">${new Date(r.created_at).toISOString()}</td>
    </tr>
  `).join('');

  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>CloudEvo Order & Transaction Tracker - Case 4</title>
    </head>
    <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f8fafc;margin:0;padding:40px;">
      <div style="max-width:860px;margin:0 auto;background:#fff;padding:32px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.05);">
        <h1 style="margin:0 0 8px 0;color:#0f172a;font-size:26px;">CloudEvo Order & Transaction Tracker</h1>
        <p style="margin:0 0 14px 0;color:#475569;font-size:15px;">
          <b>Active Architecture:</b> Case 4 - Hosting 1 Web on EC2 + 1 DB on Amazon RDS (Cloud-Native Production)
        </p>
        ${badgeHtml}
        <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:24px;">
          <div style="background:#f8fafc;padding:14px;border-radius:8px;border:1px solid #e2e8f0;">
            <div style="font-size:12px;color:#64748b;font-weight:600;">Web Container / Hostname</div>
            <div style="font-size:15px;color:#0f172a;font-weight:700;margin-top:4px;">${os.hostname()}</div>
          </div>
          <div style="background:#f8fafc;padding:14px;border-radius:8px;border:1px solid #e2e8f0;">
            <div style="font-size:12px;color:#64748b;font-weight:600;">Server Time (UTC)</div>
            <div style="font-size:15px;color:#0f172a;font-weight:700;margin-top:4px;">${new Date().toISOString()}</div>
          </div>
          <div style="background:#f8fafc;padding:14px;border-radius:8px;border:1px solid #e2e8f0;">
            <div style="font-size:12px;color:#64748b;font-weight:600;">Health Endpoint</div>
            <div style="font-size:15px;margin-top:4px;"><a href="/health" style="color:#2563eb;font-weight:600;">/health (JSON Status)</a></div>
          </div>
        </div>

        <form method="POST" action="/api/transactions" style="display:flex;gap:12px;margin-bottom:28px;">
          <input type="text" name="customer" placeholder="Customer / Transaction Note" required
            style="flex:1;padding:10px 14px;border:1px solid #cbd5e1;border-radius:6px;font-size:14px;">
          <input type="number" step="0.01" name="amount" value="1250.00" required
            style="width:140px;padding:10px 14px;border:1px solid #cbd5e1;border-radius:6px;font-size:14px;">
          <button type="submit"
            style="background:#0f172a;color:#fff;border:none;padding:10px 20px;border-radius:6px;font-weight:600;cursor:pointer;">
            + Record Transaction
          </button>
        </form>

        <h3 style="margin:0 0 12px 0;color:#0f172a;font-size:16px;">Recent Transactions (Latest 10)</h3>
        <table style="width:100%;border-collapse:collapse;text-align:left;font-size:14px;">
          <thead>
            <tr style="background:#f8fafc;border-bottom:2px solid #e2e8f0;">
              <th style="padding:12px;color:#475569;">ID</th>
              <th style="padding:12px;color:#475569;">Customer</th>
              <th style="padding:12px;color:#475569;">Amount</th>
              <th style="padding:12px;color:#475569;">Timestamp</th>
            </tr>
          </thead>
          <tbody>
            ${rowsHtml}
          </tbody>
        </table>
      </div>
    </body>
    </html>
  `);
});

app.listen(PORT, () => console.log('CloudEvo Case 4 Web running on port ' + PORT));
EOF

# 5. Tạo Dockerfile
cat << 'EOF' > /opt/cloudevo/app/Dockerfile
FROM node:18-alpine
WORKDIR /usr/src/app
COPY package.json ./
RUN npm install --omit=dev
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
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_connect_timeout 2s;
            proxy_read_timeout 3s;
        }
    }
}
EOF

# 7. Tạo docker-compose.yml kết nối tới Amazon RDS
cat << EOF > /opt/cloudevo/docker-compose.yml
version: '3.8'
services:
  cloudevo-web:
    build: ./app
    container_name: cloudevo-web
    restart: always
    environment:
      - PORT=3000
      - STORAGE_MODE=postgres
      - DB_HOST=${RDS_ENDPOINT}
      - DB_PORT=${DB_PORT}
      - DB_NAME=${DB_NAME}
      - DB_USER=${DB_USER}
      - DB_PASS=${DB_PASS}

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

docker compose up -d --build
echo "=== [CASE 4] WEB EC2 CONNECTED TO RDS SUCCESSFULLY ==="