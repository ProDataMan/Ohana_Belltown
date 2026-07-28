function escapeHtmlRewards(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

const categoryLabels = {
  photo: 'Added a photo',
  price: 'Updated a price',
  special: 'Marked a special',
  event: 'Added an event',
  social: 'Social media post',
  other: 'Other',
  redeemed: 'Redeemed',
};

let staffById = {};

async function loadStaffOptions() {
  const select = document.getElementById('award-staff-select');
  try {
    const response = await staffFetch('/api/users');
    if (!response.ok) throw new Error(`Unable to load staff (${response.status}).`);
    const users = await response.json();
    staffById = Object.fromEntries(users.map((u) => [u.id, u]));
    select.innerHTML = users
      .filter((u) => u.active !== false)
      .map((u) => `<option value="${u.id}">${escapeHtmlRewards(u.displayName)} (@${escapeHtmlRewards(u.username)})</option>`)
      .join('');
  } catch (error) {
    select.innerHTML = `<option value="">${escapeHtmlRewards(error.message)}</option>`;
  }
}

function staffName(id) {
  const u = staffById[id];
  return u ? u.displayName : id;
}

async function loadCards() {
  const listEl = document.getElementById('cards-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/staff-rewards');
    if (!response.ok) throw new Error(`Unable to load staff rewards (${response.status}).`);
    const cards = await response.json();

    if (!cards.length) {
      listEl.innerHTML = '<p class="hint">No punches awarded yet.</p>';
      return;
    }

    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Staff</th><th>Punches</th><th>Total Redeemed</th><th></th></tr></thead>
          <tbody>
            ${cards
              .map(
                (c) => `
              <tr data-staff-id="${c.staffId}">
                <td>${escapeHtmlRewards(staffName(c.staffId))}</td>
                <td>
                  <span class="pill ${c.punches >= 10 ? 'pill-approved' : ''}">${c.punches} / 10</span>
                </td>
                <td>${c.totalRedeemed}</td>
                <td>${
                  c.punches >= 10
                    ? '<button type="button" class="secondary redeem-btn">Redeem reward</button>'
                    : ''
                }</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;

    listEl.querySelectorAll('.redeem-btn').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const staffId = btn.closest('tr').dataset.staffId;
        const note = prompt('What was given for this reward? (optional)') || '';
        btn.disabled = true;
        try {
          const response = await staffFetch(
            `/api/staff-rewards/${encodeURIComponent(staffId)}/redeem${note ? `?note=${encodeURIComponent(note)}` : ''}`,
            { method: 'POST' }
          );
          if (!response.ok) throw new Error(`Failed (${response.status}).`);
          await loadCards();
          await loadEvents();
        } catch (error) {
          alert(error.message);
          btn.disabled = false;
        }
      });
    });
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlRewards(error.message)}</p>`;
  }
}

async function loadEvents() {
  const listEl = document.getElementById('events-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/staff-rewards/events?limit=50');
    if (!response.ok) throw new Error(`Unable to load activity (${response.status}).`);
    const events = await response.json();

    if (!events.length) {
      listEl.innerHTML = '<p class="hint">No activity yet.</p>';
      return;
    }

    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>When</th><th>Staff</th><th>Reason</th><th>Note</th><th>Granted by</th></tr></thead>
          <tbody>
            ${events
              .map(
                (e) => `
              <tr>
                <td>${new Date(e.createdAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</td>
                <td>${escapeHtmlRewards(staffName(e.staffId))}</td>
                <td><span class="pill ${e.category === 'redeemed' ? 'pill-approved' : ''}">${escapeHtmlRewards(categoryLabels[e.category] || e.category)}</span></td>
                <td>${escapeHtmlRewards(e.note || '')}</td>
                <td>${e.awardedBy ? escapeHtmlRewards(staffName(e.awardedBy)) : '<span class="hint">auto</span>'}</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlRewards(error.message)}</p>`;
  }
}

document.getElementById('award-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('award-status');
  const staffId = document.getElementById('award-staff-select').value;
  const category = document.getElementById('award-category-select').value;
  const noteInput = document.getElementById('award-note-input');
  if (!staffId) {
    statusEl.textContent = 'Pick a staff member first.';
    statusEl.classList.add('status-error');
    return;
  }
  statusEl.textContent = 'Awarding...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/staff-rewards/award', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ staffId, category, note: noteInput.value.trim() || null }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    statusEl.textContent = 'Punch awarded!';
    statusEl.classList.add('status-ok');
    noteInput.value = '';
    await loadCards();
    await loadEvents();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

document.getElementById('reload-cards-btn').addEventListener('click', loadCards);
document.getElementById('reload-events-btn').addEventListener('click', loadEvents);

(async () => {
  await loadStaffOptions();
  await loadCards();
  await loadEvents();
})();
