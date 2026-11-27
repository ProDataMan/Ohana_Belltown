// Staff Daily Specials page: edits DailySpecialsData (GET
// /api/daily-specials/edit, PUT /api/daily-specials). Dishes are picked from
// the live menu by name.

const SPECIAL_DAYS = [
  [2, 'Monday'], [3, 'Tuesday'], [4, 'Wednesday'], [5, 'Thursday'], [6, 'Friday'], [7, 'Saturday'], [1, 'Sunday'],
];
let menuItemNames = [];

function escapeHtmlSpecials(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function specialRow(special = { id: '', weekday: 2, title: '', deal: '', details: '', itemNames: [], active: true }) {
  const picked = new Set(special.itemNames);
  return `
    <section class="panel daily-special-row" data-id="${escapeHtmlSpecials(special.id)}">
      <div class="hours-admin-row">
        <label>Day
          <select class="sp-weekday">
            ${SPECIAL_DAYS.map(([n, name]) => `<option value="${n}" ${n === special.weekday ? 'selected' : ''}>${name}</option>`).join('')}
          </select>
        </label>
        <label class="featured-toggle"><input type="checkbox" class="sp-active" ${special.active ? 'checked' : ''} /> On</label>
        <button type="button" class="secondary sp-remove">Remove</button>
      </div>
      <label>Name <input type="text" class="sp-title" maxlength="40" placeholder="Musubi Monday" value="${escapeHtmlSpecials(special.title)}" required /></label>
      <label>Deal <input type="text" class="sp-deal" maxlength="40" placeholder="$5.50 musubis" value="${escapeHtmlSpecials(special.deal)}" required /></label>
      <label>Fine print <span class="hint">(optional)</span> <input type="text" class="sp-details" maxlength="120" value="${escapeHtmlSpecials(special.details || '')}" /></label>
      <details ${special.itemNames.length ? '' : 'open'}>
        <summary>Dishes it covers (${special.itemNames.length} picked)</summary>
        <input type="search" class="sp-filter" placeholder="Filter dishes..." />
        <div class="sp-items">
          ${menuItemNames
            .map((name) => `<label class="sp-item"><input type="checkbox" value="${escapeHtmlSpecials(name)}" ${picked.has(name) ? 'checked' : ''} /> ${escapeHtmlSpecials(name)}</label>`)
            .join('')}
          ${special.itemNames
            .filter((name) => !menuItemNames.includes(name))
            .map((name) => `<label class="sp-item"><input type="checkbox" value="${escapeHtmlSpecials(name)}" checked /> ${escapeHtmlSpecials(name)} <span class="hint">(not on the menu right now)</span></label>`)
            .join('')}
        </div>
      </details>
    </section>
  `;
}

async function loadSpecials() {
  const [specialsResponse, menuResponse] = await Promise.all([staffFetch('/api/daily-specials/edit'), fetch('/api/menu')]);
  const status = document.getElementById('specials-save-status');
  if (!specialsResponse.ok) {
    status.textContent = `Couldn't load the daily specials (${specialsResponse.status}).`;
    return;
  }
  const data = await specialsResponse.json();
  if (menuResponse.ok) {
    const menu = await menuResponse.json();
    menuItemNames = [...new Set((menu.categories || []).flatMap((c) => (c.items || []).map((i) => i.name)))].sort((a, b) => a.localeCompare(b));
  }
  document.getElementById('special-rows').innerHTML = data.specials.map(specialRow).join('');
}

function collectSpecials() {
  return {
    specials: Array.from(document.querySelectorAll('.daily-special-row')).map((row) => ({
      id: row.dataset.id || '',
      weekday: Number(row.querySelector('.sp-weekday').value),
      title: row.querySelector('.sp-title').value.trim(),
      deal: row.querySelector('.sp-deal').value.trim(),
      details: row.querySelector('.sp-details').value.trim() || null,
      itemNames: Array.from(row.querySelectorAll('.sp-items input:checked')).map((cb) => cb.value),
      active: row.querySelector('.sp-active').checked,
    })),
  };
}

document.getElementById('add-special-btn').addEventListener('click', () => {
  document.getElementById('special-rows').insertAdjacentHTML('beforeend', specialRow());
});

document.getElementById('special-rows').addEventListener('click', (event) => {
  const remove = event.target.closest('.sp-remove');
  if (remove) remove.closest('.daily-special-row').outerHTML = '';
});

document.getElementById('special-rows').addEventListener('input', (event) => {
  if (!event.target.classList.contains('sp-filter')) return;
  const query = event.target.value.trim().toLowerCase();
  event.target.closest('details').querySelectorAll('.sp-item').forEach((label) => {
    label.hidden = Boolean(query) && !label.textContent.toLowerCase().includes(query);
  });
});

document.getElementById('specials-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('specials-save-status');
  statusEl.className = 'status';
  statusEl.textContent = 'Saving...';
  const response = await staffFetch('/api/daily-specials', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(collectSpecials()),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    statusEl.className = 'status status-error';
    statusEl.textContent = body.reason || `Couldn't save (${response.status}).`;
    return;
  }
  statusEl.className = 'status status-ok';
  statusEl.textContent = 'Saved.';
  await loadSpecials();
});

loadSpecials();
