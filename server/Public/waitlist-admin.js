function escapeHtmlWaitlist(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function smsHref(phone, body) {
  const digits = phone.replace(/\D/g, '');
  const withCountryCode = digits.length === 10 ? `+1${digits}` : `+${digits}`;
  return `sms:${withCountryCode}?body=${encodeURIComponent(body)}`;
}

function minutesWaiting(createdAt) {
  const minutes = Math.round((Date.now() - new Date(createdAt).getTime()) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes === 1) return '1 min';
  return `${minutes} min`;
}

const waitlistListEl = document.getElementById('waitlist-list');

// Floor-map table ids for the "Seated at" picker — recording the table lets
// QR Insights report wait times and how soon a seated party scans the menu.
let seatingTableIds = [];
const seatingTablesLoaded = fetch('/api/table-map')
  .then((r) => (r.ok ? r.json() : []))
  .then((entries) => {
    seatingTableIds = entries.map((e) => e.id).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  })
  .catch(() => {});

async function loadWaitlist() {
  try {
    const response = await staffFetch('/api/waitlist');
    if (!response.ok) throw new Error(`Unable to load the waitlist (${response.status}).`);
    const entries = await response.json();
    await seatingTablesLoaded;
    if (!entries.length) {
      waitlistListEl.innerHTML = '<p class="hint">Nobody\'s on the waitlist right now.</p>';
      return;
    }
    waitlistListEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead>
            <tr><th>Name</th><th>Phone</th><th>Party</th><th>Note</th><th>Waiting</th><th>Status</th><th></th></tr>
          </thead>
          <tbody>
            ${entries
              .map(
                (e) => `
              <tr data-id="${e.id}">
                <td>${escapeHtmlWaitlist(e.name)}</td>
                <td>${escapeHtmlWaitlist(e.phone)}</td>
                <td>${e.partySize}</td>
                <td>${escapeHtmlWaitlist(e.note || '')}</td>
                <td>${minutesWaiting(e.createdAt)}</td>
                <td><span class="pill ${e.status === 'notified' ? 'pill-approved' : ''}">${e.status}</span></td>
                <td>
                  <a class="cta-button secondary" style="padding: 0.35rem 0.7rem; font-size: 0.82rem;"
                     href="${smsHref(e.phone, `Hi ${e.name}, your table at Ohana Belltown is ready!`)}"
                     data-notify-id="${e.id}">Text they're ready</a>
                  <span class="waitlist-seat">
                    <select class="seat-table" aria-label="Table for ${escapeHtmlWaitlist(e.name)}">
                      <option value="">Table…</option>
                      ${seatingTableIds.map((id) => `<option value="${escapeHtmlWaitlist(id)}">${escapeHtmlWaitlist(id)}</option>`).join('')}
                    </select>
                    <button type="button" class="secondary seat-btn">Seated</button>
                  </span>
                  <button type="button" class="secondary remove-btn">Remove</button>
                </td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;

    waitlistListEl.querySelectorAll('[data-notify-id]').forEach((link) => {
      link.addEventListener('click', () => {
        staffFetch(`/api/waitlist/${link.dataset.notifyId}/notify`, { method: 'POST' }).catch(() => {});
      });
    });
    waitlistListEl.querySelectorAll('.seat-btn').forEach((btn) => {
      btn.addEventListener('click', async (event) => {
        const row = event.target.closest('tr');
        const table = row.querySelector('.seat-table').value;
        if (!table) {
          row.querySelector('.seat-table').focus();
          return;
        }
        await staffFetch(`/api/waitlist/${row.dataset.id}/seat`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ table }),
        });
        await loadWaitlist();
      });
    });
    waitlistListEl.querySelectorAll('.remove-btn').forEach((btn) => {
      btn.addEventListener('click', async (event) => {
        const id = event.target.closest('tr').dataset.id;
        await staffFetch(`/api/waitlist/${id}/remove`, { method: 'POST' });
        await loadWaitlist();
      });
    });
  } catch (error) {
    waitlistListEl.innerHTML = `<p class="status status-error">${escapeHtmlWaitlist(error.message)}</p>`;
  }
}

document.getElementById('reload-waitlist-btn').addEventListener('click', loadWaitlist);

loadWaitlist();
setInterval(loadWaitlist, 30000);
