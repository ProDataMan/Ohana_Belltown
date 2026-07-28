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

// Only self-reporting can produce this category with no admin attached —
// auto-detected categories (photo/price/special/event) never go through
// here, and an approved "social" request always carries the reviewer's id.
const selfReportableCategories = ['other'];

function grantedByLabel(e) {
  if (e.awardedBy) return escapeHtmlRewards(staffName(e.awardedBy));
  if (selfReportableCategories.includes(e.category)) return '<span class="hint">self-reported</span>';
  return '<span class="hint">auto</span>';
}

let staffById = {};
let catalogItems = [];

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

async function loadSocialRequests() {
  const listEl = document.getElementById('social-requests-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/staff-rewards/social-requests');
    if (!response.ok) throw new Error(`Unable to load requests (${response.status}).`);
    const requests = await response.json();

    if (!requests.length) {
      listEl.innerHTML = '<p class="hint">No requests yet.</p>';
      return;
    }

    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>When</th><th>Staff</th><th>Link</th><th>Note</th><th>Status</th><th></th></tr></thead>
          <tbody>
            ${requests
              .map(
                (r) => `
              <tr data-id="${r.id}">
                <td>${new Date(r.createdAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</td>
                <td>${escapeHtmlRewards(staffName(r.staffId))}</td>
                <td><a href="${escapeHtmlRewards(r.link)}" target="_blank" rel="noopener">View post</a></td>
                <td>${escapeHtmlRewards(r.note || '')}</td>
                <td><span class="pill ${r.status === 'approved' ? 'pill-approved' : r.status === 'denied' ? 'pill-denied' : ''}">${escapeHtmlRewards(r.status)}</span></td>
                <td>${
                  r.status === 'pending'
                    ? `
                  <button type="button" class="secondary approve-request-btn">Approve</button>
                  <button type="button" class="secondary deny-request-btn">Deny</button>
                `
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

    async function review(id, approve, btn) {
      btn.disabled = true;
      try {
        const response = await staffFetch(`/api/staff-rewards/social-requests/${encodeURIComponent(id)}/review`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ approve }),
        });
        if (!response.ok) throw new Error(`Failed (${response.status}).`);
        await loadSocialRequests();
        await loadCards();
        await loadEvents();
      } catch (error) {
        alert(error.message);
        btn.disabled = false;
      }
    }

    listEl.querySelectorAll('.approve-request-btn').forEach((btn) => {
      btn.addEventListener('click', () => review(btn.closest('tr').dataset.id, true, btn));
    });
    listEl.querySelectorAll('.deny-request-btn').forEach((btn) => {
      btn.addEventListener('click', () => review(btn.closest('tr').dataset.id, false, btn));
    });
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlRewards(error.message)}</p>`;
  }
}

document.getElementById('reload-social-requests-btn').addEventListener('click', loadSocialRequests);

function renderCatalogList() {
  const listEl = document.getElementById('catalog-list');
  if (!catalogItems.length) {
    listEl.innerHTML = '<p class="hint">No reward items yet — add one below.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Item</th><th>Point Cost</th><th></th></tr></thead>
        <tbody>
          ${catalogItems
            .map(
              (item, i) => `
            <tr data-index="${i}">
              <td><input type="text" class="catalog-name-input" value="${escapeHtmlRewards(item.name)}" /></td>
              <td><input type="number" min="1" class="catalog-cost-input" value="${item.pointCost ?? ''}" placeholder="Not priced yet" style="max-width: 10rem;" /></td>
              <td><button type="button" class="secondary catalog-remove-btn">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.catalog-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const index = Number(btn.closest('tr').dataset.index);
      catalogItems.splice(index, 1);
      renderCatalogList();
    });
  });
}

async function loadCatalog() {
  try {
    const response = await staffFetch('/api/staff-rewards/catalog');
    if (!response.ok) throw new Error(`Unable to load the reward catalog (${response.status}).`);
    catalogItems = await response.json();
    renderCatalogList();
  } catch (error) {
    document.getElementById('catalog-list').innerHTML = `<p class="status status-error">${escapeHtmlRewards(error.message)}</p>`;
  }
}

document.getElementById('catalog-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const nameInput = document.getElementById('new-catalog-name-input');
  const costInput = document.getElementById('new-catalog-cost-input');
  const name = nameInput.value.trim();
  if (!name) return;
  catalogItems.push({
    id: `item-${Date.now()}`,
    name,
    pointCost: costInput.value ? Number(costInput.value) : null,
  });
  nameInput.value = '';
  costInput.value = '';
  renderCatalogList();
});

document.getElementById('save-catalog-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('catalog-status');
  // Pull current values back out of the editable rows before saving, so
  // in-place edits (not just adds/removes) are captured too.
  const rows = document.querySelectorAll('#catalog-list tr[data-index]');
  const updated = Array.from(rows).map((row, i) => {
    const name = row.querySelector('.catalog-name-input').value.trim();
    const costRaw = row.querySelector('.catalog-cost-input').value;
    return { id: catalogItems[i].id, name, pointCost: costRaw ? Number(costRaw) : null };
  });
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/staff-rewards/catalog', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updated),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    catalogItems = await response.json();
    renderCatalogList();
    statusEl.textContent = 'Catalog saved!';
    statusEl.classList.add('status-ok');
    await loadCards();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

document.getElementById('reload-catalog-btn').addEventListener('click', loadCatalog);

async function loadCards() {
  const listEl = document.getElementById('cards-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/staff-rewards');
    if (!response.ok) throw new Error(`Unable to load staff rewards (${response.status}).`);
    const cards = await response.json();

    if (!cards.length) {
      listEl.innerHTML = '<p class="hint">No points awarded yet.</p>';
      return;
    }

    const pricedItems = catalogItems.filter((item) => item.pointCost && item.pointCost > 0);

    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Staff</th><th>Points</th><th>Total Redeemed</th><th>Redeem</th></tr></thead>
          <tbody>
            ${cards
              .map((c) => {
                const affordable = pricedItems.filter((item) => item.pointCost <= c.points);
                return `
              <tr data-staff-id="${c.staffId}">
                <td>${escapeHtmlRewards(staffName(c.staffId))}</td>
                <td>
                  <span class="pill ${affordable.length ? 'pill-approved' : ''}">${c.points} pts</span>
                </td>
                <td>${c.totalRedeemed}</td>
                <td>${
                  affordable.length
                    ? `
                  <select class="redeem-item-select">
                    ${affordable.map((item) => `<option value="${item.id}">${escapeHtmlRewards(item.name)} (${item.pointCost} pts)</option>`).join('')}
                  </select>
                  <button type="button" class="secondary redeem-btn">Redeem</button>
                `
                    : '<span class="hint">Not enough points yet</span>'
                }</td>
              </tr>
            `;
              })
              .join('')}
          </tbody>
        </table>
      </div>
    `;

    listEl.querySelectorAll('.redeem-btn').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const row = btn.closest('tr');
        const staffId = row.dataset.staffId;
        const catalogItemId = row.querySelector('.redeem-item-select').value;
        const note = prompt('Anything to note about this redemption? (optional)') || '';
        btn.disabled = true;
        try {
          const response = await staffFetch(`/api/staff-rewards/${encodeURIComponent(staffId)}/redeem`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ catalogItemId, note: note || null }),
          });
          if (!response.ok) {
            const body = await response.json().catch(() => ({}));
            throw new Error(body.reason || `Failed (${response.status}).`);
          }
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
          <thead><tr><th>When</th><th>Staff</th><th>Reason</th><th>Points</th><th>Note</th><th>Granted by</th></tr></thead>
          <tbody>
            ${events
              .map(
                (e) => `
              <tr>
                <td>${new Date(e.createdAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</td>
                <td>${escapeHtmlRewards(staffName(e.staffId))}</td>
                <td><span class="pill ${e.category === 'redeemed' ? 'pill-approved' : ''}">${escapeHtmlRewards(categoryLabels[e.category] || e.category)}</span></td>
                <td>${e.points > 0 ? `+${e.points}` : e.points}</td>
                <td>${escapeHtmlRewards(e.note || '')}</td>
                <td>${grantedByLabel(e)}</td>
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
    statusEl.textContent = 'Points awarded!';
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
  await loadSocialRequests();
  await loadCatalog();
  await loadCards();
  await loadEvents();
})();
