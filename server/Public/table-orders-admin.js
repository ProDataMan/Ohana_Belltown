function escapeHtmlTableOrders(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function minutesAgoTableOrder(createdAt) {
  const minutes = Math.round((Date.now() - new Date(createdAt).getTime()) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes === 1) return '1 min ago';
  return `${minutes} min ago`;
}

const tableOrdersListEl = document.getElementById('table-orders-list');

async function loadTableOrders() {
  try {
    const response = await staffFetch('/api/table-orders/pending');
    if (!response.ok) throw new Error(`Unable to load table orders (${response.status}).`);
    const orders = await response.json();
    if (!orders.length) {
      tableOrdersListEl.innerHTML = '<p class="hint">No pending table orders right now.</p>';
      return;
    }
    tableOrdersListEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Table</th><th>Item</th><th>Placed</th><th></th></tr></thead>
          <tbody>
            ${orders
              .map(
                (o) => `
              <tr data-id="${o.id}">
                <td><span class="pill pill-approved">Table ${escapeHtmlTableOrders(o.tableId)}</span></td>
                <td>${escapeHtmlTableOrders(o.itemName)}</td>
                <td>${minutesAgoTableOrder(o.createdAt)}</td>
                <td><button type="button" class="secondary acknowledge-btn">Acknowledge</button></td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;

    tableOrdersListEl.querySelectorAll('.acknowledge-btn').forEach((btn) => {
      btn.addEventListener('click', async (event) => {
        const id = event.target.closest('tr').dataset.id;
        await staffFetch(`/api/table-orders/${id}/acknowledge`, { method: 'POST' });
        await loadTableOrders();
      });
    });
  } catch (error) {
    tableOrdersListEl.innerHTML = `<p class="status status-error">${escapeHtmlTableOrders(error.message)}</p>`;
  }
}

document.getElementById('reload-table-orders-btn').addEventListener('click', loadTableOrders);

loadTableOrders();
setInterval(loadTableOrders, 15000);
