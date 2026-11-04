// Fake voters. Each state has its own party "lean" so the map looks realistic.
const API = process.env.API_URL || 'http://localhost:4000';
const RATE = +process.env.VOTES_PER_SEC || 10;
const PARTIES = ['APC', 'PDP', 'LP', 'NNPP', 'ADC'];
const STATES = ['Abia','Adamawa','Akwa Ibom','Anambra','Bauchi','Bayelsa','Benue','Borno','Cross River','Delta','Ebonyi','Edo','Ekiti','Enugu','FCT Abuja','Gombe','Imo','Jigawa','Kaduna','Kano','Katsina','Kebbi','Kogi','Kwara','Lagos','Nasarawa','Niger','Ogun','Ondo','Osun','Oyo','Plateau','Rivers','Sokoto','Taraba','Yobe','Zamfara'];
const lean = Object.fromEntries(STATES.map(s => [s, PARTIES.map(() => 0.5 + Math.random() * 2)]));

function pick(state) {
  const w = lean[state]; let r = Math.random() * w.reduce((a, b) => a + b);
  for (let i = 0; i < w.length; i++) if ((r -= w[i]) < 0) return PARTIES[i];
  return PARTIES[0];
}
setInterval(async () => {
  const state = STATES[Math.floor(Math.random() * STATES.length)];
  try {
    await fetch(`${API}/api/vote`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ state, party: pick(state) }) });
  } catch (e) { console.log('API not ready:', e.message); }
}, 1000 / RATE);
