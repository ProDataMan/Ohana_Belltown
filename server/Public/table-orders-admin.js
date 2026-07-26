function escapeHtmlTableOrders(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function minutesAgoTableOrder(timestamp) {
  const minutes = Math.round((Date.now() - new Date(timestamp).getTime()) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes === 1) return '1 min ago';
  return `${minutes} min ago`;
}

const needsEntryEl = document.getElementById('needs-entry-list');
const awaitingDeliveryEl = document.getElementById('awaiting-delivery-list');

function itemDisplayName(order) {
  const base = escapeHtmlTableOrders(order.itemName);
  if (!order.modifiers || !order.modifiers.length) return base;
  return `${base} <span class="hint">+ ${order.modifiers.map(escapeHtmlTableOrders).join(', ')}</span>`;
}

function renderNeedsEntry(orders) {
  if (!orders.length) {
    needsEntryEl.innerHTML = '<p class="hint">Nothing needs entering right now.</p>';
    return;
  }
  needsEntryEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Table</th><th>Item</th><th>Placed</th><th></th></tr></thead>
        <tbody>
          ${orders
            .map(
              (o) => `
            <tr data-id="${o.id}">
              <td><span class="pill pill-approved">Table ${escapeHtmlTableOrders(o.tableId)}</span></td>
              <td>${itemDisplayName(o)}</td>
              <td>${minutesAgoTableOrder(o.createdAt)}</td>
              <td><button type="button" class="secondary enter-btn">Confirm Entered</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  needsEntryEl.querySelectorAll('.enter-btn').forEach((btn) => {
    btn.addEventListener('click', async (event) => {
      const id = event.target.closest('tr').dataset.id;
      await staffFetch(`/api/table-orders/${id}/enter`, { method: 'POST' });
      await loadTableOrders();
    });
  });
}

function renderAwaitingDelivery(orders) {
  if (!orders.length) {
    awaitingDeliveryEl.innerHTML = '<p class="hint">Nothing awaiting delivery right now.</p>';
    return;
  }
  const now = Date.now();
  awaitingDeliveryEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Table</th><th>Item</th><th>Entered</th><th>Status</th><th></th></tr></thead>
        <tbody>
          ${orders
            .map((o) => {
              const isReady = o.estimatedReadyAt && new Date(o.estimatedReadyAt).getTime() <= now;
              return `
              <tr data-id="${o.id}">
                <td><span class="pill pill-approved">Table ${escapeHtmlTableOrders(o.tableId)}</span></td>
                <td>${escapeHtmlTableOrders(o.itemName)}</td>
                <td>${minutesAgoTableOrder(o.enteredAt || o.createdAt)}</td>
                <td>${isReady ? '<span class="pill pill-warning">Ready now</span>' : '<span class="pill">Cooking</span>'}</td>
                <td><button type="button" class="secondary deliver-btn">Confirm Delivered</button></td>
              </tr>
            `;
            })
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  awaitingDeliveryEl.querySelectorAll('.deliver-btn').forEach((btn) => {
    btn.addEventListener('click', async (event) => {
      const id = event.target.closest('tr').dataset.id;
      await staffFetch(`/api/table-orders/${id}/deliver`, { method: 'POST' });
      await loadTableOrders();
    });
  });
}

async function loadTableOrders() {
  try {
    const response = await staffFetch('/api/table-orders/dashboard');
    if (!response.ok) throw new Error(`Unable to load table orders (${response.status}).`);
    const data = await response.json();
    renderNeedsEntry(data.needsEntry);
    renderAwaitingDelivery(data.awaitingDelivery);
  } catch (error) {
    const message = `<p class="status status-error">${escapeHtmlTableOrders(error.message)}</p>`;
    needsEntryEl.innerHTML = message;
    awaitingDeliveryEl.innerHTML = message;
  }
}

async function loadStaffing() {
  try {
    const response = await staffFetch('/api/table-orders/staffing');
    if (!response.ok) return;
    const config = await response.json();
    document.getElementById('staffing-input').value = config.staffOnDuty;
  } catch {
    // leave the input at its default
  }
}

document.getElementById('staffing-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('staffing-status');
  const staffOnDuty = Number(document.getElementById('staffing-input').value);
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/table-orders/staffing', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ staffOnDuty }),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    statusEl.textContent = 'Updated!';
    statusEl.classList.add('status-ok');
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

document.getElementById('reload-table-orders-btn').addEventListener('click', loadTableOrders);

loadStaffing();
loadTableOrders();
setInterval(loadTableOrders, 15000);
