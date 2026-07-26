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

async function loadWaitlist() {
  try {
    const response = await staffFetch('/api/waitlist');
    if (!response.ok) throw new Error(`Unable to load the waitlist (${response.status}).`);
    const entries = await response.json();
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
