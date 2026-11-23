// Staff Hours page: edits BusinessHoursData (GET /api/hours/edit, PUT
// /api/hours) and shows the result as guests will see it (GET /api/hours).

const DAY_NAMES = ['', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const DISPLAY_ORDER = [2, 3, 4, 5, 6, 7, 1];

function escapeHtmlHours(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function weekRow(day) {
  return `
    <div class="hours-admin-row" data-weekday="${day.weekday}">
      <strong>${DAY_NAMES[day.weekday]}</strong>
      <label class="featured-toggle"><input type="checkbox" class="day-closed" ${day.closed ? 'checked' : ''} /> Closed</label>
      <label>Opens <input type="time" class="day-open" value="${escapeHtmlHours(day.open)}" /></label>
      <label>Closes <input type="time" class="day-close" value="${escapeHtmlHours(day.close)}" /></label>
      <label>Kitchen closes <input type="time" class="day-kitchen" value="${escapeHtmlHours(day.kitchenClose || '')}" /></label>
    </div>
  `;
}

function exceptionRow(e = { date: '', closed: true, open: '', close: '', kitchenClose: '', note: '' }) {
  return `
    <div class="hours-admin-row exception-row">
      <label>Date <input type="date" class="ex-date" value="${escapeHtmlHours(e.date)}" required /></label>
      <label>What <input type="text" class="ex-note" maxlength="40" placeholder="e.g. Thanksgiving" value="${escapeHtmlHours(e.note || '')}" /></label>
      <label class="featured-toggle"><input type="checkbox" class="ex-closed" ${e.closed ? 'checked' : ''} /> Closed all day</label>
      <label>Opens <input type="time" class="ex-open" value="${escapeHtmlHours(e.open || '')}" /></label>
      <label>Closes <input type="time" class="ex-close" value="${escapeHtmlHours(e.close || '')}" /></label>
      <label>Kitchen closes <input type="time" class="ex-kitchen" value="${escapeHtmlHours(e.kitchenClose || '')}" /></label>
      <button type="button" class="secondary ex-remove">Remove</button>
    </div>
  `;
}

async function loadPreview() {
  const el = document.getElementById('hours-preview');
  const response = await fetch('/api/hours');
  if (!response.ok) {
    el.innerHTML = `<p class="status status-error">Couldn't load the preview (${response.status}).</p>`;
    return;
  }
  const h = await response.json();
  el.innerHTML = `
    <p class="hours-status ${h.now.open ? 'hours-open' : 'hours-closed'}">${escapeHtmlHours(h.now.label)}</p>
    <p>${escapeHtmlHours(h.now.today)}${h.now.kitchenLabel ? ` · ${escapeHtmlHours(h.now.kitchenLabel)}` : ''}${h.now.happyHourLabel ? ` · ${escapeHtmlHours(h.now.happyHourLabel)}` : ''}</p>
    <ul class="hours-week">${h.week.map((l) => `<li><span>${escapeHtmlHours(l.label)}</span> <span>${escapeHtmlHours(l.hours)}</span></li>`).join('')}</ul>
    ${h.kitchenSummary ? `<p class="hours-note">${escapeHtmlHours(h.kitchenSummary)}</p>` : ''}
    ${h.happyHourSummary ? `<p class="hours-note">Happy Hour ${escapeHtmlHours(h.happyHourSummary)} <span class="hint">(Mon–Fri 3–6pm, during opening hours)</span></p>` : ''}
    ${h.upcoming.length ? `<p class="hours-note">Coming up: ${h.upcoming.map((u) => `${escapeHtmlHours(u.label)}: ${escapeHtmlHours(u.hours)}`).join(' · ')}</p>` : ''}
  `;
}

async function loadHours() {
  const response = await staffFetch('/api/hours/edit');
  if (!response.ok) {
    document.getElementById('hours-save-status').textContent = `Couldn't load the hours (${response.status}).`;
    return;
  }
  const data = await response.json();
  document.getElementById('season-label').value = data.seasonLabel || '';
  document.getElementById('holiday-note').value = data.holidayNote || '';
  document.getElementById('week-rows').innerHTML = DISPLAY_ORDER.map((weekday) => weekRow(data.week.find((d) => d.weekday === weekday))).join('');
  document.getElementById('exception-rows').innerHTML = data.exceptions.map(exceptionRow).join('');
}

function collect() {
  const week = Array.from(document.querySelectorAll('#week-rows .hours-admin-row')).map((row) => ({
    weekday: Number(row.dataset.weekday),
    closed: row.querySelector('.day-closed').checked,
    open: row.querySelector('.day-open').value || '00:00',
    close: row.querySelector('.day-close').value || '00:00',
    kitchenClose: row.querySelector('.day-kitchen').value || null,
  }));
  const exceptions = Array.from(document.querySelectorAll('#exception-rows .exception-row')).map((row) => {
    const closed = row.querySelector('.ex-closed').checked;
    return {
      date: row.querySelector('.ex-date').value,
      closed,
      open: closed ? null : row.querySelector('.ex-open').value || null,
      close: closed ? null : row.querySelector('.ex-close').value || null,
      kitchenClose: closed ? null : row.querySelector('.ex-kitchen').value || null,
      note: row.querySelector('.ex-note').value.trim() || null,
    };
  });
  return {
    seasonLabel: document.getElementById('season-label').value.trim() || null,
    holidayNote: document.getElementById('holiday-note').value.trim() || null,
    week,
    exceptions,
  };
}

document.getElementById('add-exception-btn').addEventListener('click', () => {
  document.getElementById('exception-rows').insertAdjacentHTML('beforeend', exceptionRow());
});

document.getElementById('exception-rows').addEventListener('click', (event) => {
  const remove = event.target.closest('.ex-remove');
  if (remove) remove.closest('.exception-row').outerHTML = '';
});

document.getElementById('hours-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('hours-save-status');
  statusEl.className = 'status';
  statusEl.textContent = 'Saving...';
  const response = await staffFetch('/api/hours', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(collect()),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    statusEl.className = 'status status-error';
    statusEl.textContent = body.reason || `Couldn't save (${response.status}).`;
    return;
  }
  statusEl.className = 'status status-ok';
  statusEl.textContent = 'Saved. The site now shows these hours.';
  await loadHours();
  await loadPreview();
});

loadHours();
loadPreview();
