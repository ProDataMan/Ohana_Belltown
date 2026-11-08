// QR Insights report: renders /api/analytics/qr-insights (see QRInsightsBuilder
// server-side) as a floor-map heat map plus comparison tables.

const INSIGHT_SECTION_LABELS = { dining: 'Dining', bar: 'Bar', sushi: 'Sushi Bar', deck: 'Deck', none: 'No table (front door)' };
const WEEKDAY_LABELS = ['', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
let insights = null;
let activeHeatSection = 'dining';

function escapeHtmlInsights(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function sectionLabel(section) {
  return INSIGHT_SECTION_LABELS[section] || section;
}

function pct(value) {
  return value == null ? '—' : `${Math.round(value * 100)}%`;
}

function seconds(value) {
  if (value == null) return '—';
  if (value < 60) return `${Math.round(value)}s`;
  const minutes = Math.round(value / 60);
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function pills(el, list) {
  el.innerHTML = list.filter(Boolean).map((p) => `<span class="pill ${p.cls || ''}">${escapeHtmlInsights(p.label)}</span>`).join('');
}

function table(headers, rows) {
  if (!rows.length) return '<p class="hint">No data yet.</p>';
  return `
    <div class="data-table">
      <table>
        <thead><tr>${headers.map((h) => `<th>${h}</th>`).join('')}</tr></thead>
        <tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('')}</tbody>
      </table>
    </div>
  `;
}

/// 0–4 heat level relative to the busiest value shown.
function heatLevel(value, max) {
  if (!value || !max) return 0;
  return Math.max(1, Math.ceil((value / max) * 4));
}

function renderOverview() {
  const d = insights;
  const scanned = d.tables.filter((t) => t.visits > 0).length;
  pills(document.getElementById('insights-overview'), [
    { label: `${d.totalVisits} visits`, cls: 'pill-approved' },
    { label: `${scanned} of ${d.tables.length} tables scanned` },
    { label: `${d.returning.devices} phones` },
    d.returning.devices ? { label: `${pct(d.returning.returningDevices / d.returning.devices)} came back` } : null,
    d.parties.avgPhonesPerParty != null ? { label: `${d.parties.avgPhonesPerParty.toFixed(1)} phones per party` } : null,
  ]);
}

function renderHeatMap() {
  const sections = ['dining', 'bar', 'sushi', 'deck'].filter((s) => insights.tables.some((t) => t.section === s));
  const tabs = document.getElementById('heat-tabs');
  tabs.innerHTML = sections
    .map((s) => {
      const visits = insights.tables.filter((t) => t.section === s).reduce((sum, t) => sum + t.visits, 0);
      return `<button type="button" data-section="${s}" class="${s === activeHeatSection ? 'active' : ''}">${sectionLabel(s)} (${visits})</button>`;
    })
    .join('');
  tabs.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      activeHeatSection = btn.dataset.section;
      renderHeatMap();
    });
  });

  const max = Math.max(0, ...insights.tables.map((t) => t.visits));
  document.getElementById('heat-legend').innerHTML = [0, 1, 2, 3, 4]
    .map((level) => `<span class="floor-map-legend-item"><span class="floor-map-dot heat-${level}"></span> ${level === 0 ? 'No visits' : level === 4 ? 'Busiest' : ''}</span>`)
    .join('');

  const canvas = document.getElementById('heat-canvas');
  canvas.innerHTML = insights.tables
    .filter((t) => t.section === activeHeatSection)
    .map(
      (t) => `
        <button type="button"
          class="floor-map-table shape-${escapeHtmlInsights(t.shape)} heat-${heatLevel(t.visits, max)}"
          data-table="${escapeHtmlInsights(t.table)}"
          style="left: ${t.x}%; top: ${t.y}%;"
          title="Table ${escapeHtmlInsights(t.table)}: ${t.visits} visits"
        >${escapeHtmlInsights(t.table)}<span class="heat-count">${t.visits}</span></button>
      `
    )
    .join('');
  canvas.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      const t = insights.tables.find((x) => x.table === btn.dataset.table);
      const last = t.lastVisitAt ? new Date(t.lastVisitAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) : 'never';
      document.getElementById('heat-detail').innerHTML =
        `<strong>Table ${escapeHtmlInsights(t.table)}</strong>: ${t.visits} visits from ${t.devices} phones, ${t.detailViews} item opens, ` +
        `avg. visit ${seconds(t.avgDurationSeconds)}, last scan ${escapeHtmlInsights(last)}. ` +
        `<a href="/qr-visits.html">See visits</a>`;
    });
  });

  const unscanned = insights.tables.filter((t) => t.visits === 0).map((t) => t.table);
  document.getElementById('heat-unscanned').innerHTML = unscanned.length
    ? `<strong>No scans in this range:</strong> ${unscanned.map(escapeHtmlInsights).join(', ')}`
    : 'Every table was scanned at least once in this range.';
}

function renderSections() {
  const rows = insights.sections.map((s) => [
    escapeHtmlInsights(sectionLabel(s.section)),
    s.section === 'none' ? '—' : `${s.tablesWithVisits} of ${s.tableCount}`,
    s.visits,
    seconds(s.avgDurationSeconds),
    s.firstTapSamples ? seconds(s.avgFirstTapSeconds) : '—',
    pct(s.openedItemRate),
    pct(s.returningRate),
    escapeHtmlInsights(s.deviceMix.map((m) => `${m.label} ${m.count}`).join(', ') || '—'),
  ]);
  document.getElementById('section-table').innerHTML = table(
    ['Section', 'Tables used', 'Visits', 'Avg. visit', 'Time to first tap', 'Opened an item', 'Returning', 'Phones'],
    rows
  );

  document.getElementById('section-items').innerHTML = insights.sections
    .filter((s) => s.topItems.length)
    .map(
      (s) => `
        <div>
          <h3>${escapeHtmlInsights(sectionLabel(s.section))}</h3>
          <ol class="insights-list">
            ${s.topItems.map((i) => `<li>${escapeHtmlInsights(i.label)} <span class="hint">${i.count}</span></li>`).join('')}
          </ol>
        </div>
      `
    )
    .join('') || '<p class="hint">No item opens yet.</p>';
}

/// Rows = sections, columns = hour or weekday buckets, cells shaded by count.
function renderTimeGrid(el, buckets, columns, label) {
  if (!buckets.length) {
    el.innerHTML = '<p class="hint">No data yet.</p>';
    return;
  }
  const sections = [...new Set(buckets.map((b) => b.section))].sort(
    (a, b) => Object.keys(INSIGHT_SECTION_LABELS).indexOf(a) - Object.keys(INSIGHT_SECTION_LABELS).indexOf(b)
  );
  const count = (bucket, section) => buckets.filter((b) => b.bucket === bucket && (!section || b.section === section)).reduce((sum, b) => sum + b.visits, 0);
  const max = Math.max(...columns.map((c) => Math.max(...sections.map((s) => count(c, s)))));
  const cell = (value) => `<td class="heat-cell heat-${heatLevel(value, max)}">${value || ''}</td>`;
  el.innerHTML = `
    <div class="data-table insights-grid">
      <table>
        <thead><tr><th></th>${columns.map((c) => `<th>${label(c)}</th>`).join('')}</tr></thead>
        <tbody>
          ${sections.map((s) => `<tr><th>${escapeHtmlInsights(sectionLabel(s))}</th>${columns.map((c) => cell(count(c, s))).join('')}</tr>`).join('')}
          <tr><th>All</th>${columns.map((c) => `<td><strong>${count(c) || ''}</strong></td>`).join('')}</tr>
        </tbody>
      </table>
    </div>
  `;
}

function hourLabel(hour) {
  const suffix = hour < 12 ? 'a' : 'p';
  return `${hour % 12 === 0 ? 12 : hour % 12}${suffix}`;
}

function renderTimes() {
  const hours = insights.byHour.map((b) => b.bucket);
  // Show the span the restaurant actually gets scans in, not all 24 hours.
  const first = hours.length ? Math.min(...hours) : 11;
  const last = hours.length ? Math.max(...hours) : 22;
  const hourColumns = Array.from({ length: last - first + 1 }, (_, i) => first + i);
  renderTimeGrid(document.getElementById('by-hour'), insights.byHour, hourColumns, hourLabel);
  renderTimeGrid(document.getElementById('by-weekday'), insights.byWeekday, [2, 3, 4, 5, 6, 7, 1], (d) => WEEKDAY_LABELS[d]);
}

function renderHappyHour() {
  const h = insights.happyHour;
  pills(document.getElementById('happy-hour-summary'), [
    { label: `${h.cardVisits} Happy Hour card scan${h.cardVisits === 1 ? '' : 's'}`, cls: 'pill-approved' },
    h.cardVisits ? { label: `${pct(h.cardStayedOnHappyHour / h.cardVisits)} stayed on Happy Hour` } : null,
    h.cardVisits ? { label: `${pct(h.cardWentToOtherPages / h.cardVisits)} also browsed the full menu` } : null,
    { label: `${h.visitsDuringHappyHour} visits during Happy Hour (M–F 3–6pm)` },
    h.visitsDuringHappyHour ? { label: `${pct(h.duringHappyHourOpenedHappyHourItem / h.visitsDuringHappyHour)} of those opened a Happy Hour item` } : null,
  ]);
  document.getElementById('happy-hour-items').innerHTML = h.cardTopItems.length
    ? `<h3>Most-opened from the Happy Hour card</h3>${table(['Item', 'Visits'], h.cardTopItems.map((i) => [escapeHtmlInsights(i.label), i.count]))}`
    : '';
}

function money(value) {
  return value == null ? '—' : `$${value.toFixed(2)}`;
}

function renderPos() {
  const p = insights.pos;
  const summary = document.getElementById('pos-summary');
  const unmatched = document.getElementById('pos-unmatched');
  if (!p) {
    summary.innerHTML = '<span class="pill">No POS tickets imported for this range yet.</span>';
    unmatched.innerHTML = '';
    return;
  }
  pills(summary, [
    { label: `${p.orders} tickets imported`, cls: 'pill-approved' },
    { label: `${p.tableOrdersWithQRVisit} of ${p.tableOrders} table tickets had a QR visit (${pct(p.tableOrders ? p.tableOrdersWithQRVisit / p.tableOrders : null)})` },
    { label: `${p.qrVisitsWithOrder} of ${p.qrVisitsWithTable} table QR visits matched a ticket` },
    { label: `Per guest with QR: ${money(p.avgNetSalesWithQR)}, ${p.avgItemsWithQR != null ? p.avgItemsWithQR.toFixed(1) : '—'} items` },
    { label: `Per guest without QR: ${money(p.avgNetSalesWithoutQR)}, ${p.avgItemsWithoutQR != null ? p.avgItemsWithoutQR.toFixed(1) : '—'} items` },
  ]);
  unmatched.innerHTML = p.unmatchedPosItems.length
    ? `<h3>POS items that don't match a website menu item</h3>
       <p class="hint">These can't be lined up with what people looked at until the names match (or are close: "Spam Musubi (2pc)" matches "Spam Musubi"). Rename on one side if they're the same dish.</p>
       ${table(['POS item', 'Tickets'], p.unmatchedPosItems.map((i) => [escapeHtmlInsights(i.label), i.count]))}`
    : '';
}

function renderItems() {
  const hasPos = Boolean(insights.pos);
  const rows = insights.items.map((i) => {
    const flags = [];
    if (!i.onMenu) flags.push('<span class="pill">no longer on menu</span>');
    else if (!i.hasPhoto) flags.push('<span class="pill pill-warning">no photo</span>');
    const row = [`${escapeHtmlInsights(i.itemName)} ${flags.join(' ')}`, i.visits, i.detailViews, i.photoTaps, i.addedToOrder];
    if (hasPos) row.push(`${i.visitsThatOrdered} (${pct(i.visits ? i.visitsThatOrdered / i.visits : null)})`, i.timesOrdered);
    return row;
  });
  const headers = ['Item', 'Visits that opened it', 'Opens', 'Photo taps', 'Added to order'];
  if (hasPos) headers.push('Opened, then ordered', 'Tickets with it');
  document.getElementById('item-table').innerHTML = table(headers, rows);
}

function renderSearches() {
  const empties = insights.searches.filter((s) => s.emptyCount > 0).sort((a, b) => b.emptyCount - a.emptyCount);
  pills(
    document.getElementById('empty-searches'),
    empties.length
      ? empties.map((s) => ({ label: `"${s.query}" found nothing ×${s.emptyCount}`, cls: 'pill-warning' }))
      : [{ label: 'No empty searches.', cls: 'pill-approved' }]
  );
  document.getElementById('search-table').innerHTML = table(
    ['Search', 'Times', 'Found nothing'],
    insights.searches.map((s) => [`"${escapeHtmlInsights(s.query)}"`, s.count, s.emptyCount || ''])
  );
}

function renderPaths() {
  document.getElementById('path-table').innerHTML = table(
    ['Pages', 'Visits'],
    insights.paths.map((p) => [p.pages.map(escapeHtmlInsights).join(' &rarr; '), p.visits])
  );
}

function renderGuests() {
  const r = insights.returning;
  const p = insights.parties;
  pills(document.getElementById('guests-summary'), [
    { label: `${r.devices} phones` },
    { label: `${r.returningDevices} returning (${r.visitsFromReturningDevices} visits)` },
    r.multiVisitDevicesInRange ? { label: `${r.sameSectionDevices} of ${r.multiVisitDevicesInRange} repeat phones always sat in the same section` } : null,
    { label: `${p.parties} parties` },
  ]);
  document.getElementById('party-table').innerHTML = table(
    ['Phones that scanned', 'Parties'],
    p.phonesPerParty.map((c) => [c.label, c.count])
  );
  document.getElementById('device-table').innerHTML = table(
    ['Phone', 'Visits'],
    insights.deviceMix.map((c) => [escapeHtmlInsights(c.label), c.count])
  );
}

async function loadInsights() {
  const days = document.getElementById('insights-range').value;
  document.getElementById('insights-overview').innerHTML = '<span class="hint">Loading...</span>';
  try {
    const response = await staffFetch(`/api/analytics/qr-insights?days=${encodeURIComponent(days)}`);
    if (!response.ok) throw new Error(`Unable to load QR insights (${response.status}).`);
    insights = await response.json();
    renderOverview();
    renderHeatMap();
    renderSections();
    renderTimes();
    renderHappyHour();
    renderPos();
    renderItems();
    renderSearches();
    renderPaths();
    renderGuests();
  } catch (error) {
    document.getElementById('insights-overview').innerHTML = `<p class="status status-error">${escapeHtmlInsights(error.message)}</p>`;
  }
}

document.getElementById('insights-range').addEventListener('change', loadInsights);
loadInsights();
