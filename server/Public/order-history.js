function escapeHtmlOrderHistory(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// Same helper as menu-section.js's getDeviceId() — duplicated rather than
// shared, since these are separate plain <script> files with no module
// loader between them (this page doesn't otherwise load menu-section.js,
// which assumes a menu page's DOM). Reads the same localStorage key, so a
// guest lands on the same device id whether they got here from the cart
// modal or came straight to this page.
function getDeviceId() {
  let id = localStorage.getItem('ohana_device_id');
  if (id) return id;
  id = window.crypto && window.crypto.randomUUID
    ? window.crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}-${Math.random().toString(16).slice(2)}`;
  localStorage.setItem('ohana_device_id', id);
  return id;
}

function orderStatusLabel(order) {
  if (order.status === 'delivered') return 'Delivered';
  if (order.status === 'entered') return 'Being prepared';
  if (order.status === 'cancelled') return 'Cancelled';
  return 'Sent to staff';
}

async function loadOrderHistory() {
  const el = document.getElementById('order-history-list');
  el.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await fetch(`/api/table-orders/device-history?deviceId=${encodeURIComponent(getDeviceId())}`);
    if (!response.ok) throw new Error(`Unable to load order history (${response.status}).`);
    const orders = await response.json();
    if (!orders.length) {
      el.innerHTML = '<p class="hint">No orders yet from this device — once you order from a table, it\'ll show up here.</p>';
      return;
    }
    el.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Item</th><th>Table</th><th>Status</th><th>Ordered</th></tr></thead>
          <tbody>
            ${orders
              .map(
                (o) => `
              <tr>
                <td>${escapeHtmlOrderHistory(o.itemName)}</td>
                <td>${escapeHtmlOrderHistory(o.tableId)}</td>
                <td><span class="pill ${o.status === 'delivered' ? 'pill-approved' : o.status === 'cancelled' ? 'pill-denied' : ''}">${orderStatusLabel(o)}</span></td>
                <td>${new Date(o.createdAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    el.innerHTML = `<p class="status status-error">${escapeHtmlOrderHistory(error.message)}</p>`;
  }
}

document.getElementById('reload-order-history-btn').addEventListener('click', loadOrderHistory);

loadOrderHistory();
