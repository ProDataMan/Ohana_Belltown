function escapeHtmlGC(str) {
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadOrders() {
  const listEl = document.getElementById('orders-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/gift-cards/orders');
    if (!response.ok) throw new Error(`Unable to load orders (${response.status}).`);
    const orders = await response.json();
    renderOrdersList(orders.filter((o) => o.status !== 'pendingPayment'));
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlGC(error.message)}</p>`;
  }
}

function renderOrdersList(orders) {
  const listEl = document.getElementById('orders-list');
  if (!orders.length) {
    listEl.innerHTML = '<p class="hint">No paid gift card orders yet.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Amount</th><th>Buyer</th><th>Recipient / Note</th><th>Status</th><th>Paid</th><th></th></tr></thead>
        <tbody>
          ${orders
            .map(
              (o) => `
            <tr data-id="${escapeHtmlGC(o.id)}">
              <td>$${o.amount.toFixed(2)}</td>
              <td>${escapeHtmlGC(o.buyerName)}<div class="hint">${escapeHtmlGC(o.buyerEmail)}</div></td>
              <td>${o.recipientName ? escapeHtmlGC(o.recipientName) : '<span class="hint">&mdash;</span>'}${o.note ? `<div class="hint">${escapeHtmlGC(o.note)}</div>` : ''}</td>
              <td><span class="pill ${o.status === 'fulfilled' ? 'pill-approved' : 'pill-warning'}">${escapeHtmlGC(o.status)}</span></td>
              <td>${escapeHtmlGC(o.paidAt || '')}</td>
              <td>${o.status === 'paid' ? '<button type="button" class="secondary order-fulfill-btn">Mark Fulfilled</button>' : ''}</td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.order-fulfill-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = btn.closest('tr').dataset.id;
      btn.disabled = true;
      try {
        const response = await staffFetch(`/api/gift-cards/orders/${encodeURIComponent(id)}/fulfill`, { method: 'POST' });
        if (!response.ok) throw new Error(`Failed (${response.status}).`);
        loadOrders();
      } catch (error) {
        btn.disabled = false;
      }
    });
  });
}

document.getElementById('reload-orders-btn').addEventListener('click', loadOrders);

loadOrders();
