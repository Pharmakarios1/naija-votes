import React, { useEffect, useState } from 'react';

const COLORS = { APC: '#1f6fd1', PDP: '#c8102e', LP: '#0b8a3e', NNPP: '#e8820c', ADC: '#6b3fa0' };
const fmt = n => n.toLocaleString('en-NG');

export default function App() {
  const [data, setData] = useState(null);
  const [live, setLive] = useState(false);
  const [state, setState] = useState('Lagos');
  const [msg, setMsg] = useState('');

  useEffect(() => {
    const es = new EventSource('/api/stream');
    es.onopen = () => setLive(true);
    es.onerror = () => setLive(false);
    es.onmessage = e => setData(JSON.parse(e.data));
    return () => es.close();
  }, []);

  async function vote(party) {
    const r = await fetch('/api/vote', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ state, party }) });
    setMsg(r.ok ? `Your vote for ${party} in ${state} has been recorded.` : 'Vote failed. Check that the API is running.');
  }

  if (!data) return <p className="loading">Collecting results from the polling units…</p>;

  const leader = s => data.parties.reduce((a, b) => (data.states[s][a] >= data.states[s][b] ? a : b));
  const stateWins = Object.fromEntries(data.parties.map(p => [p, 0]));
  Object.keys(data.states).forEach(s => { if (Object.values(data.states[s]).some(v => v)) stateWins[leader(s)]++; });
  const ranked = [...data.parties].sort((a, b) => data.national[b] - data.national[a]);
  const max = Math.max(1, ...Object.values(data.national));

  return (
    <>
      <div className="flag"><i /><i /><i /></div>
      <header>
        <p className="sim">Simulation only. Parties are real, candidates and numbers are not.</p>
        <h1>Naija Votes</h1>
        <p className="sub">Live presidential election results, 36 states and the FCT.</p>
        <span className={live ? 'pill on' : 'pill'}>{live ? 'Live' : 'Reconnecting'}</span>
      </header>

      <main>
        <section className="collation">
          <h2>National collation <small>{fmt(data.total)} votes counted</small></h2>
          {ranked.map((p, i) => (
            <div className="row" key={p}>
              <b className="party" style={{ background: COLORS[p] }}>{p}</b>
              <div className="bar"><span style={{ width: `${(data.national[p] / max) * 100}%`, background: COLORS[p] }} /></div>
              <span className="num">{fmt(data.national[p])}</span>
              <span className="wins">{stateWins[p]} states</span>
              {i === 0 && data.total > 0 && <em className="lead">Leading</em>}
            </div>
          ))}
        </section>

        <section className="cast">
          <h2>Cast a test vote</h2>
          <select value={state} onChange={e => setState(e.target.value)}>{Object.keys(data.states).map(s => <option key={s}>{s}</option>)}</select>
          <div className="btns">{data.parties.map(p => <button key={p} style={{ background: COLORS[p] }} onClick={() => vote(p)}>{p}</button>)}</div>
          <p className="msg" role="status">{msg}</p>
        </section>

        <section className="states">
          <h2>Results by state</h2>
          <div className="grid">
            {Object.keys(data.states).map(s => {
              const tot = Object.values(data.states[s]).reduce((a, b) => a + b, 0);
              const l = leader(s);
              return (
                <div className="st" key={s} style={{ borderLeftColor: tot ? COLORS[l] : '#ccc' }}>
                  <strong>{s}</strong>
                  <span>{tot ? `${l} leads, ${Math.round((data.states[s][l] / tot) * 100)}%` : 'Awaiting results'}</span>
                  <small>{fmt(tot)} votes</small>
                </div>
              );
            })}
          </div>
        </section>
      </main>
    </>
  );
}
