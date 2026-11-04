import express from 'express';
import pg from 'pg';
import Redis from 'ioredis';

const PARTIES = ['APC', 'PDP', 'LP', 'NNPP', 'ADC'];
const STATES = ['Abia','Adamawa','Akwa Ibom','Anambra','Bauchi','Bayelsa','Benue','Borno','Cross River','Delta','Ebonyi','Edo','Ekiti','Enugu','FCT Abuja','Gombe','Imo','Jigawa','Kaduna','Kano','Katsina','Kebbi','Kogi','Kwara','Lagos','Nasarawa','Niger','Ogun','Ondo','Osun','Oyo','Plateau','Rivers','Sokoto','Taraba','Yobe','Zamfara'];
const CHANNEL = 'votes';

// Local: DATABASE_URL. AWS: PGHOST/PGUSER/PGPASSWORD/PGDATABASE env vars + DB_SSL=true (RDS requires TLS)
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : undefined });
const pub = new Redis(process.env.REDIS_URL);
const sub = new Redis(process.env.REDIS_URL);
const app = express();
app.use(express.json());

async function init() {
  for (let i = 0; i < 20; i++) {           // retry until DB is ready
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS votes (id BIGSERIAL PRIMARY KEY, state TEXT NOT NULL, party TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now());
        CREATE TABLE IF NOT EXISTS tallies (state TEXT, party TEXT, count BIGINT DEFAULT 0, PRIMARY KEY (state, party));`);
      return;
    } catch { await new Promise(r => setTimeout(r, 1500)); }
  }
  throw new Error('DB unavailable');
}

async function snapshot() {
  const { rows } = await pool.query('SELECT state, party, count FROM tallies');
  const states = Object.fromEntries(STATES.map(s => [s, Object.fromEntries(PARTIES.map(p => [p, 0]))]));
  const national = Object.fromEntries(PARTIES.map(p => [p, 0]));
  for (const r of rows) { states[r.state][r.party] = +r.count; national[r.party] += +r.count; }
  return { parties: PARTIES, national, states, total: Object.values(national).reduce((a, b) => a + b, 0), at: Date.now() };
}

app.get('/health', (_, res) => res.json({ ok: true, instance: process.env.HOSTNAME }));

app.post('/api/vote', async (req, res) => {
  const { state, party } = req.body || {};
  if (!STATES.includes(state) || !PARTIES.includes(party)) return res.status(400).json({ error: 'Invalid state or party' });
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await c.query('INSERT INTO votes(state, party) VALUES ($1,$2)', [state, party]);
    await c.query('INSERT INTO tallies(state, party, count) VALUES ($1,$2,1) ON CONFLICT (state, party) DO UPDATE SET count = tallies.count + 1', [state, party]);
    await c.query('COMMIT');
    try { await pub.publish(CHANNEL, '1'); }   // tell every API replica; a Redis outage must not fail a saved vote
    catch (e) { console.error('publish failed', e.message); }
    res.status(201).json({ saved: true, instance: process.env.HOSTNAME });
  } catch (e) { await c.query('ROLLBACK'); res.status(500).json({ error: 'Could not save vote' }); }
  finally { c.release(); }
});

app.get('/api/results', async (_, res) => res.json(await snapshot()));

// Server-Sent Events: pushed at most once a second whenever any replica saw a new vote
const clients = new Set();
let dirty = false;
app.get('/api/stream', async (req, res) => {
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
  res.write(`data: ${JSON.stringify(await snapshot())}\n\n`);
  clients.add(res);
  req.on('close', () => clients.delete(res));
});
sub.subscribe(CHANNEL);
sub.on('message', () => { dirty = true; });
setInterval(async () => {
  if (!dirty || !clients.size) return;
  dirty = false;
  const data = `data: ${JSON.stringify(await snapshot())}\n\n`;
  clients.forEach(c => c.write(data));
}, 1000);

// Heartbeat keeps load balancers (ALB idle timeout) from dropping quiet SSE connections
setInterval(() => clients.forEach(c => c.write(': ping\n\n')), 20000);

await init();
app.listen(4000, () => console.log('API listening on 4000'));
