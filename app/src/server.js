const express = require("express");
const os = require("os");
const { Pool } = require("pg");

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const PORT = process.env.PORT || 3000;
const STORAGE_MODE = process.env.STORAGE_MODE || "memory"; // 'memory' hoặc 'postgres'
const SCENARIO_NAME =
  process.env.SCENARIO_NAME || "Case 1: Single EC2 (Stateless Web)";

// Bộ nhớ tạm cho Trường hợp 1 (STORAGE_MODE=memory)
const memoryTransactions = [
  {
    id: 1,
    customer: "CoderPush Benchmark Init",
    amount: 150.0,
    created_at: new Date().toISOString(),
  },
];

// Cấu hình kết nối PostgreSQL cho Trường hợp 2, 3, 4 (STORAGE_MODE=postgres)
let pool = null;
if (STORAGE_MODE === "postgres") {
  pool = new Pool({
    host: process.env.DB_HOST || "localhost",
    port: parseInt(process.env.DB_PORT || "5432", 10),
    user: process.env.DB_USER || "postgres",
    password: process.env.DB_PASS || "postgres123",
    database: process.env.DB_NAME || "cloudevo",
    connectionTimeoutMillis: 3000,
  });

  // Tự động khởi tạo bảng transactions khi chạy ở chế độ postgres
  const initDb = async () => {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS transactions (
          id SERIAL PRIMARY KEY,
          customer VARCHAR(100) NOT NULL,
          amount NUMERIC(12, 2) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);
      console.log("[DB] Bảng transactions đã sẵn sàng.");
    } catch (err) {
      console.error("[DB] Lỗi khởi tạo bảng:", err.message);
    }
  };
  initDb();
}

// 1. Endpoint kiểm tra sức khỏe (/health) để đo RTO bằng dr_monitor.py
app.get("/health", async (req, res) => {
  const start = Date.now();
  let dbConnected = false;
  let dbLatencyMs = 0;

  if (STORAGE_MODE === "memory") {
    dbConnected = false;
    dbLatencyMs = 0;
  } else if (pool) {
    try {
      await pool.query("SELECT 1");
      dbConnected = true;
      dbLatencyMs = Date.now() - start;
    } catch (err) {
      dbConnected = false;
      dbLatencyMs = Date.now() - start;
      return res.status(503).json({
        status: "DOWN",
        mode: STORAGE_MODE,
        db_connected: false,
        db_latency_ms: dbLatencyMs,
        error: err.message,
        hostname: os.hostname(),
        server_time: new Date().toISOString(),
      });
    }
  }

  res.status(200).json({
    status: "UP",
    mode: STORAGE_MODE,
    db_connected: dbConnected,
    db_latency_ms: dbLatencyMs,
    hostname: os.hostname(),
    server_time: new Date().toISOString(),
  });
});

// 2. API lấy danh sách giao dịch
app.get("/api/transactions", async (req, res) => {
  try {
    if (STORAGE_MODE === "memory") {
      return res.json({
        mode: "memory",
        count: memoryTransactions.length,
        data: memoryTransactions.slice(-20).reverse(),
      });
    }
    const result = await pool.query(
      "SELECT * FROM transactions ORDER BY id DESC LIMIT 20",
    );
    res.json({ mode: "postgres", count: result.rowCount, data: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 3. API thêm giao dịch mới
app.post("/api/transactions", async (req, res) => {
  const customer = req.body.customer || "Anonymous User";
  const amount = parseFloat(req.body.amount || "99.99");

  try {
    if (STORAGE_MODE === "memory") {
      const newTx = {
        id: memoryTransactions.length + 1,
        customer,
        amount,
        created_at: new Date().toISOString(),
      };
      memoryTransactions.push(newTx);
      if (req.headers.accept && req.headers.accept.includes("text/html")) {
        return res.redirect("/");
      }
      return res.status(201).json(newTx);
    }

    const result = await pool.query(
      "INSERT INTO transactions (customer, amount) VALUES ($1, $2) RETURNING *",
      [customer, amount],
    );
    if (req.headers.accept && req.headers.accept.includes("text/html")) {
      return res.redirect("/");
    }
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 4. Giao diện Web UI trực quan
app.get("/", async (req, res) => {
  let transactions = [];
  let dbStatusText = "IN-MEMORY (No External DB)";
  let statusColor = "#2563eb";

  if (STORAGE_MODE === "memory") {
    transactions = [...memoryTransactions].reverse().slice(0, 10);
  } else {
    try {
      const result = await pool.query(
        "SELECT * FROM transactions ORDER BY id DESC LIMIT 10",
      );
      transactions = result.rows;
      dbStatusText = `CONNECTED (PostgreSQL @ ${process.env.DB_HOST || "localhost"})`;
      statusColor = "#16a34a";
    } catch (err) {
      dbStatusText = `DISCONNECTED (${err.message})`;
      statusColor = "#dc2626";
    }
  }

  const rowsHtml = transactions
    .map(
      (t) => `
    <tr>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;">#${t.id}</td>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;">${t.customer}</td>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;font-weight:bold;color:#059669;">$${Number(t.amount).toFixed(2)}</td>
      <td style="padding:10px;border-bottom:1px solid #e5e7eb;color:#6b7280;">${new Date(t.created_at).toISOString()}</td>
    </tr>
  `,
    )
    .join("");

  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <title>CloudEvo AWS Benchmark</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f3f4f6; margin: 0; padding: 24px; color: #1f2937; }
        .container { max-width: 900px; margin: 0 auto; background: #fff; padding: 28px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
        .badge { display: inline-block; padding: 6px 12px; border-radius: 6px; color: #fff; font-weight: 600; font-size: 14px; background: ${statusColor}; }
        .meta-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin: 20px 0; }
        .meta-box { background: #f9fafb; border: 1px solid #e5e7eb; padding: 14px; border-radius: 8px; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th { background: #f9fafb; text-align: left; padding: 10px; border-bottom: 2px solid #e5e7eb; }
        input, button { padding: 10px 14px; border-radius: 6px; border: 1px solid #d1d5db; font-size: 14px; }
        button { background: #111827; color: #fff; border: none; cursor: pointer; font-weight: 600; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1 style="margin-top:0;">CloudEvo Order & Transaction Tracker</h1>
        <p style="color:#4b5563;font-size:16px;"><strong>Active Architecture:</strong> ${SCENARIO_NAME}</p>
        <div><span class="badge">Storage Mode: ${STORAGE_MODE.toUpperCase()} — ${dbStatusText}</span></div>

        <div class="meta-grid">
          <div class="meta-box"><strong>Container / Hostname</strong><br/><span style="color:#4b5563;">${os.hostname()}</span></div>
          <div class="meta-box"><strong>Server Time (UTC)</strong><br/><span style="color:#4b5563;">${new Date().toISOString()}</span></div>
          <div class="meta-box"><strong>Health Endpoint</strong><br/><a href="/health" target="_blank">/health (JSON Check)</a></div>
        </div>

        <form method="POST" action="/api/transactions" style="display:flex;gap:10px;margin:20px 0;">
          <input type="text" name="customer" placeholder="Customer / Transaction Note" required style="flex:1;" />
          <input type="number" step="0.01" name="amount" placeholder="Amount ($)" value="250.00" required style="width:140px;" />
          <button type="submit">+ Record Transaction</button>
        </form>

        <h3>Recent Transactions (Latest 10)</h3>
        <table>
          <thead>
            <tr><th>ID</th><th>Customer</th><th>Amount</th><th>Timestamp</th></tr>
          </thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>
    </body>
    </html>
  `);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(
    `[CloudEvo] Server running on port ${PORT} in ${STORAGE_MODE} mode`,
  );
});
