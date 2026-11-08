// Staff QR visit report: loads every QR visit for one day from
// /api/analytics/qr-visits and filters by table in the browser, so the
// table dropdown can list exactly the tables that had visits that day.

const VISIT_TIME_ZONE = 'America/Los_Angeles';
let dayVisits = [];

function escapeHtmlVisits(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function todayInRestaurantTime() {
  // en-CA formats as YYYY-MM-DD.
  return new Intl.DateTimeFormat('en-CA', { timeZone: VISIT_TIME_ZONE }).format(new Date());
}

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString(undefined, { timeZone: VISIT_TIME_ZONE, hour: 'numeric', minute: '2-digit' });
}

function formatDuration(seconds) {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const minutes = Math.round(seconds / 60);
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function tableLabel(visit) {
  if (visit.table) return `Table ${visit.table}`;
  return visit.source === 'happy-hour' ? 'Happy Hour QR (no table)' : 'Front door QR (no table)';
}

function whoLabel(visit) {
  if (visit.customerName) return `${visit.customerName} (signed in)`;
  return `Device ${visit.deviceId.slice(0, 6)}`;
}

/// "Pupu Platter ×2, Spam Musubi"
function itemList(counts) {
  return counts.map((c) => `${escapeHtmlVisits(c.itemName)}${c.count > 1 ? ` <span class="hint">×${c.count}</span>` : ''}`).join(', ');
}

function selectedVisits() {
  const table = document.getElementById('visit-table').value;
  return table ? dayVisits.filter((v) => (v.table || '') === table) : dayVisits;
}

function renderSummary(visits) {
  const el = document.getElementById('visits-summary');
  if (!visits.length) {
    el.innerHTML = '<span class="pill">No QR visits on this day.</span>';
    return;
  }
  const tables = new Set(visits.map((v) => v.table).filter(Boolean));
  const devices = new Set(visits.map((v) => v.customerId || v.deviceId));
  const withDetails = visits.filter((v) => v.detailViews.length).length;
  const returning = visits.filter((v) => v.previousVisits > 0).length;
  const avgSeconds = visits.reduce((sum, v) => sum + v.durationSeconds, 0) / visits.length;
  el.innerHTML = [
    `<span class="pill pill-approved">${visits.length} visit${visits.length === 1 ? '' : 's'}</span>`,
    `<span class="pill">${tables.size} table${tables.size === 1 ? '' : 's'}</span>`,
    `<span class="pill">${devices.size} device${devices.size === 1 ? '' : 's'}</span>`,
    `<span class="pill">${Math.round((withDetails / visits.length) * 100)}% opened an item</span>`,
    `<span class="pill">Avg. visit ${formatDuration(avgSeconds)}</span>`,
    returning ? `<span class="pill">${returning} returning device${returning === 1 ? '' : 's'}</span>` : '',
  ].join('');
}

function renderItemRollup(visits) {
  const el = document.getElementById('item-rollup');
  const byItem = new Map();
  visits.forEach((visit) => {
    visit.detailViews.forEach((d) => {
      if (!byItem.has(d.itemName)) byItem.set(d.itemName, { views: 0, visits: 0, tables: new Set() });
      const row = byItem.get(d.itemName);
      row.views += d.count;
      row.visits += 1;
      if (visit.table) row.tables.add(visit.table);
    });
  });
  const rows = Array.from(byItem.entries()).sort((a, b) => b[1].visits - a[1].visits || b[1].views - a[1].views);
  if (!rows.length) {
    el.innerHTML = '<p class="hint">No item detail views yet.</p>';
    return;
  }
  el.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Item</th><th>Visits</th><th>Detail views</th><th>Tables</th></tr></thead>
        <tbody>
          ${rows
            .map(
              ([name, r]) => `
            <tr>
              <td>${escapeHtmlVisits(name)}</td>
              <td>${r.visits}</td>
              <td>${r.views}</td>
              <td>${escapeHtmlVisits(Array.from(r.tables).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).join(', ') || '—')}</td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
}

const TIMELINE_LABELS = {
  start: 'Scanned QR',
  page: 'Opened page',
  details: 'Opened details',
  photo: 'Tapped photo',
  search: 'Searched',
  'add-to-order': 'Added to order',
};

function timelineText(entry) {
  const what = entry.itemName || (entry.query ? `"${entry.query}"` : entry.page) || '';
  return `${TIMELINE_LABELS[entry.type] || entry.type}${what ? `: ${what}` : ''}`;
}

function renderVisitList(visits) {
  const el = document.getElementById('visit-list');
  if (!visits.length) {
    el.innerHTML = '<p class="hint">Nothing to show.</p>';
    return;
  }
  el.innerHTML = visits
    .map(
      (v) => `
    <article class="qr-visit-card">
      <div class="qr-visit-head">
        <strong>${escapeHtmlVisits(tableLabel(v))}</strong>
        <span>${formatTime(v.startedAt)}&ndash;${formatTime(v.lastSeenAt)} (${formatDuration(v.durationSeconds)})</span>
        <span class="hint">${escapeHtmlVisits(whoLabel(v))}${v.device ? ` · ${escapeHtmlVisits(v.device)}` : ''}${v.previousVisits ? ` · visit #${v.previousVisits + 1} from this device` : ' · first visit'}</span>
      </div>
      <dl class="qr-visit-facts">
        <dt>Details opened</dt><dd>${v.detailViews.length ? itemList(v.detailViews) : '<span class="hint">none</span>'}</dd>
        ${v.photoTaps.length ? `<dt>Photos tapped</dt><dd>${itemList(v.photoTaps)}</dd>` : ''}
        ${v.searches.length ? `<dt>Searched</dt><dd>${v.searches.map((q) => `"${escapeHtmlVisits(q)}"`).join(', ')}</dd>` : ''}
        ${v.addedToOrder.length ? `<dt>Added to order</dt><dd>${v.addedToOrder.map(escapeHtmlVisits).join(', ')}</dd>` : ''}
        <dt>Pages</dt><dd>${v.pages.map(escapeHtmlVisits).join(' &rarr; ') || '<span class="hint">none</span>'}</dd>
      </dl>
      <details>
        <summary class="hint">Full timeline (${v.timeline.length} events)</summary>
        <ol class="qr-visit-timeline">
          ${v.timeline.map((t) => `<li><span class="hint">${formatTime(t.at)}</span> ${escapeHtmlVisits(timelineText(t))}</li>`).join('')}
        </ol>
      </details>
    </article>
  `
    )
    .join('');
}

function renderTableOptions() {
  const select = document.getElementById('visit-table');
  const current = select.value;
  const tables = Array.from(new Set(dayVisits.map((v) => v.table).filter(Boolean))).sort((a, b) =>
    a.localeCompare(b, undefined, { numeric: true })
  );
  select.innerHTML =
    '<option value="">All tables</option>' +
    tables.map((t) => `<option value="${escapeHtmlVisits(t)}">Table ${escapeHtmlVisits(t)}</option>`).join('');
  select.value = tables.includes(current) ? current : '';
}

function render() {
  const visits = selectedVisits();
  const date = document.getElementById('visit-date').value;
  const table = document.getElementById('visit-table').value;
  const csvParams = new URLSearchParams({ date });
  if (table) csvParams.set('table', table);
  document.getElementById('download-csv-link').href = `/api/analytics/qr-visits.csv?${csvParams}`;
  renderSummary(visits);
  renderItemRollup(visits);
  renderVisitList(visits);
}

async function loadVisits() {
  const date = document.getElementById('visit-date').value;
  const listEl = document.getElementById('visit-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch(`/api/analytics/qr-visits?date=${encodeURIComponent(date)}`);
    if (!response.ok) throw new Error(`Unable to load QR visits (${response.status}).`);
    dayVisits = await response.json();
    renderTableOptions();
    render();
  } catch (error) {
    document.getElementById('visits-summary').innerHTML = '';
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlVisits(error.message)}</p>`;
  }
}

const dateInput = document.getElementById('visit-date');
dateInput.value = new URLSearchParams(window.location.search).get('date') || todayInRestaurantTime();
dateInput.addEventListener('change', loadVisits);
document.getElementById('visit-table').addEventListener('change', render);
document.getElementById('reload-visits-btn').addEventListener('click', loadVisits);
loadVisits();
