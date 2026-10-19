#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

# TÊN S3 BUCKET DÙNG ĐỂ BACKUP 
S3_BUCKET="cloudevo-backup-dangth"

echo "=== [1/6] Cập nhật hệ thống & cài đặt Docker, AWS CLI, stress-ng ==="
apt-get update -y
apt-get install -y docker.io docker-compose-v2 unzip stress-ng postgresql-client
systemctl enable --now docker
usermod -aG docker ubuntu

# Cài đặt Docker & Docker Compose
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ubuntu

# Cài đặt AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

echo "=== [2/6] Khởi tạo thư mục dự án /opt/cloudevo ==="
mkdir -p /opt/cloudevo/app/src

cat <<'EOF' > /opt/cloudevo/app/package.json
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

cat <<'EOF' > /opt/cloudevo/app/src/server.js
const express = require('express');
const os = require('os');
const { Pool } = require('pg');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const PORT = process.env.PORT || 3000;
const STORAGE_MODE = process.env.STORAGE_MODE || 'postgres';
const SCENARIO_NAME = process.env.SCENARIO_NAME || 'Case 2 - Hosting 1 Web App + 1 DB on Single EC2 (Monolith)';

let pool = null;
let memoryTransactions = [
  { id: 1, customer: 'CloudPush Benchmark Init', amount: '250.00', created_at: new Date().toISOString() }
];

if (STORAGE_MODE === 'postgres') {
  pool = new Pool({
    host: process.env.DB_HOST || 'db',
    port: parseInt(process.env.DB_PORT || '5432'),
    user: process.env.DB_USER || 'cloudevo_user',
    password: process.env.DB_PASS || 'CloudEvoPassword123!',
    database: process.env.DB_NAME || 'cloudevo_db',
    connectionTimeoutMillis: 2000,
    query_timeout: 2500
  });
}

async function initDb() {
  if (STORAGE_MODE !== 'postgres') return;
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS transactions (
        id SERIAL PRIMARY KEY,
        customer VARCHAR(255) NOT NULL,
        amount NUMERIC(10,2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    const countRes = await pool.query('SELECT COUNT(*) FROM transactions');
    if (parseInt(countRes.rows[0].count) === 0) {
      await pool.query(
        'INSERT INTO transactions (customer, amount) VALUES ($1, $2)',
        ['CloudPush Benchmark Init (PostgreSQL)', 250.00]
      );
    }
    console.log('PostgreSQL table initialized.');
  } catch (err) {
    console.error('Waiting for PostgreSQL...', err.message);
    setTimeout(initDb, 3000);
  }
}
initDb();

// Endpoint /health phục vụ dr_monitor.py
app.get('/health', async (req, res) => {
  const start = Date.now();
  let dbConnected = false;
  let dbLatency = 0;

  if (STORAGE_MODE === 'postgres' && pool) {
    try {
      await pool.query('SELECT 1');
      dbConnected = true;
      dbLatency = Date.now() - start;
    } catch (e) {
      dbConnected = false;
      dbLatency = Date.now() - start;
      return res.status(503).json({
        status: 'DOWN',
        mode: STORAGE_MODE,
        db_connected: false,
        db_latency_ms: dbLatency,
        hostname: os.hostname(),
        server_time: new Date().toISOString()
      });
    }
  }

  res.status(200).json({
    status: 'UP',
    mode: STORAGE_MODE,
    db_connected: dbConnected,
    db_latency_ms: dbLatency,
    hostname: os.hostname(),
    server_time: new Date().toISOString()
  });
});

app.post('/api/transactions', async (req, res) => {
  const customer = req.body.customer || 'Anonymous Transaction';
  const amount = parseFloat(req.body.amount || 100.00).toFixed(2);
  if (STORAGE_MODE === 'postgres' && pool) {
    await pool.query('INSERT INTO transactions (customer, amount) VALUES ($1, $2)', [customer, amount]);
  } else {
    memoryTransactions.unshift({ id: memoryTransactions.length + 1, customer, amount, created_at: new Date().toISOString() });
  }
  res.redirect('/');
});

app.get('/', async (req, res) => {
  const start = Date.now();
  let rows = [];
  let dbConnected = false;
  let dbLatency = 0;

  if (STORAGE_MODE === 'postgres' && pool) {
    try {
      const result = await pool.query('SELECT id, customer, amount, created_at FROM transactions ORDER BY id DESC LIMIT 10');
      rows = result.rows;
      dbConnected = true;
      dbLatency = Date.now() - start;
    } catch (e) {
      dbConnected = false;
    }
  } else {
    rows = memoryTransactions.slice(0, 10);
  }

  const trHtml = rows.map(r => `
    <tr>
      <td>#${r.id}</td>
      <td>${r.customer}</td>
      <td>$${Number(r.amount).toFixed(2)}</td>
      <td>${new Date(r.created_at).toISOString().replace('T', ' ').substring(0, 19)} UTC</td>
    </tr>
  `).join('');

  res.send(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>CloudEvo Order & Transaction Tracker</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f4f6f8; margin: 0; padding: 40px; color: #1e293b; }
    .card { max-width: 820px; margin: 0 auto; background: #fff; border-radius: 12px; padding: 32px; box-shadow: 0 4px 20px rgba(0,0,0,0.06); }
    h1 { margin: 0 0 8px 0; font-size: 26px; }
    .sub { color: #64748b; font-size: 14px; margin-bottom: 14px; }
    .badge { display: inline-block; background: ${dbConnected ? '#059669' : '#dc2626'}; color: #fff; padding: 6px 14px; border-radius: 20px; font-size: 12px; font-weight: 600; margin-bottom: 24px; }
    .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; margin-bottom: 24px; }
    .box { background: #f8fafc; border: 1px solid #e2e8f0; padding: 14px; border-radius: 8px; }
    .box-label { font-size: 12px; color: #64748b; font-weight: 600; margin-bottom: 4px; }
    .box-val { font-size: 14px; font-family: monospace; }
    form { display: flex; gap: 10px; margin-bottom: 28px; }
    input[type="text"] { flex: 1; padding: 10px 12px; border: 1px solid #cbd5e1; border-radius: 6px; }
    input[type="number"] { width: 120px; padding: 10px 12px; border: 1px solid #cbd5e1; border-radius: 6px; }
    button { background: #0f172a; color: #fff; border: none; padding: 10px 18px; border-radius: 6px; font-weight: 600; cursor: pointer; }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td { text-align: left; padding: 12px; border-bottom: 1px solid #e2e8f0; }
    th { color: #475569; font-weight: 600; }
  </style>
</head>
<body>
  <div class="card">
    <h1>CloudEvo Order & Transaction Tracker</h1>
    <div class="sub"><b>Active Architecture:</b> ${SCENARIO_NAME}</div>
    <div class="badge">Storage Mode: ${STORAGE_MODE.toUpperCase()} — DB Connected: ${dbConnected ? 'TRUE (' + dbLatency + 'ms)' : 'FALSE'}</div>
    <div class="grid">
      <div class="box"><div class="box-label">Container / Hostname</div><div class="box-val">${os.hostname()}</div></div>
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
      <tbody>${trHtml}</tbody>
    </table>
  </div>
</body>
</html>`);
});

app.listen(PORT, () => console.log('Server running on port ' + PORT));
EOF

cat <<'EOF' > /opt/cloudevo/app/Dockerfile
FROM node:20-alpine
WORKDIR /usr/src/app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
EXPOSE 3000
CMD ["node", "src/server.js"]
EOF

cat <<'EOF' > /opt/cloudevo/app/nginx.conf
server {
    listen 80;
    location / {
        proxy_pass http://web:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 3s;
        proxy_read_timeout 3s;
    }
}
EOF

echo "=== [3/6] Tạo file docker-compose.yml cho Trường hợp 2 ==="
cat <<'EOF' > /opt/cloudevo/docker-compose.yml
services:
  db:
    image: postgres:15-alpine
    container_name: cloudevo-postgres
    restart: always
    environment:
      POSTGRES_USER: cloudevo_user
      POSTGRES_PASSWORD: CloudEvoPassword123!
      POSTGRES_DB: cloudevo_db
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cloudevo_user -d cloudevo_db"]
      interval: 5s
      timeout: 3s
      retries: 5

  web:
    build: ./app
    container_name: cloudevo-web
    restart: always
    environment:
      PORT: 3000
      STORAGE_MODE: postgres
      SCENARIO_NAME: "Case 2 - Hosting 1 Web App + 1 PostgreSQL DB on Single EC2 (Monolith)"
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: cloudevo_user
      DB_PASS: CloudEvoPassword123!
      DB_NAME: cloudevo_db
    depends_on:
      db:
        condition: service_healthy

  nginx:
    image: nginx:alpine
    container_name: cloudevo-nginx
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./app/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - web

volumes:
  pgdata:
EOF

echo "=== [4/6] Tạo Script Backup & Restore S3 ==="
cat <<EOF > /opt/cloudevo/backup_s3.sh
#!/bin/bash
set -e
S3_BUCKET="${S3_BUCKET}"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/tmp/db_backups"
BACKUP_FILE="\${BACKUP_DIR}/cloudevo_db_\${TIMESTAMP}.sql.gz"
mkdir -p "\$BACKUP_DIR"

echo "[\$(date)] Dang pg_dump du lieu PostgreSQL..."
docker exec cloudevo-postgres pg_dump -U cloudevo_user -d cloudevo_db --clean --if-exists | gzip > "\$BACKUP_FILE"

echo "[\$(date)] Dang day file len S3..."
aws s3 cp "\$BACKUP_FILE" "s3://\${S3_BUCKET}/case2/cloudevo_db_\${TIMESTAMP}.sql.gz"
aws s3 cp "\$BACKUP_FILE" "s3://\${S3_BUCKET}/case2/latest.sql.gz"
rm -f "\$BACKUP_FILE"
echo "[\$(date)] HOAN TAT BACKUP LEN S3: s3://\${S3_BUCKET}/case2/cloudevo_db_\${TIMESTAMP}.sql.gz"
EOF

cat <<EOF > /opt/cloudevo/restore_s3.sh
#!/bin/bash
set -e
S3_BUCKET="${S3_BUCKET}"
echo "[\$(date)] Dang tai ban backup moi nhat tu s3://\${S3_BUCKET}/case2/latest.sql.gz..."
aws s3 cp "s3://\${S3_BUCKET}/case2/latest.sql.gz" /tmp/latest.sql.gz

echo "[\$(date)] Dang nap lai du lieu vao PostgreSQL..."
gunzip -c /tmp/latest.sql.gz | docker exec -i cloudevo-postgres psql -U cloudevo_user -d cloudevo_db
rm -f /tmp/latest.sql.gz
echo "[\$(date)] KHOI PHUC DU LIEU TU S3 THANH CONG!"
EOF

chmod +x /opt/cloudevo/backup_s3.sh /opt/cloudevo/restore_s3.sh
chown -R ubuntu:ubuntu /opt/cloudevo

echo "=== [5/6] Khởi chạy Docker Compose ==="
cd /opt/cloudevo
docker compose up -d --build

echo "=== [6/6] Thiết lập Cronjob tự động Backup mỗi 1 giờ ==="
(crontab -l 2>/dev/null; echo "0 * * * * /opt/cloudevo/backup_s3.sh >> /var/log/s3_backup.log 2>&1") | crontab -
echo "=== HOÀN TẤT KHỞI TẠO CASE 2 ==="