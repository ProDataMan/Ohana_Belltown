// POS Orders admin page: Heartland sync status + manual sync, CSV upload,
// and a day's imported tickets with how many QR visits each matched.

const POS_TIME_ZONE = 'America/Los_Angeles';

function escapeHtmlPos(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function restaurantDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: POS_TIME_ZONE }).format(d);
}

function formatWhen(iso) {
  return new Date(iso).toLocaleString(undefined, { timeZone: POS_TIME_ZONE, dateStyle: 'medium', timeStyle: 'short' });
}

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString(undefined, { timeZone: POS_TIME_ZONE, hour: 'numeric', minute: '2-digit' });
}

async function errorMessage(response, fallback) {
  const body = await response.json().catch(() => ({}));
  return body.reason || `${fallback} (${response.status}).`;
}

async function loadStatus() {
  const el = document.getElementById('sync-status');
  try {
    const response = await staffFetch('/api/pos/status');
    if (!response.ok) throw new Error(await errorMessage(response, 'Unable to load status'));
    const status = await response.json();
    const pills = [
      status.apiConfigured
        ? '<span class="pill pill-approved">API connected — imports daily at 4:30am</span>'
        : '<span class="pill pill-warning">API key not set — use CSV upload, or see setup steps below</span>',
    ];
    const last = status.lastSync;
    if (last) {
      const what = last.source === 'csv' ? 'CSV upload' : `Heartland import${last.from ? ` (${last.from} to ${last.to})` : ''}`;
      pills.push(
        last.error
          ? `<span class="pill pill-denied">Last ${escapeHtmlPos(what)} failed ${escapeHtmlPos(formatWhen(last.at))}</span>`
          : `<span class="pill">Last ${escapeHtmlPos(what)}: ${last.ordersImported} tickets, ${escapeHtmlPos(formatWhen(last.at))}</span>`
      );
    } else {
      pills.push('<span class="pill">Nothing imported yet</span>');
    }
    el.innerHTML = pills.join('');
    document.getElementById('sync-result').textContent = last && last.error ? last.error : '';
    document.getElementById('sync-btn').disabled = !status.apiConfigured;
  } catch (error) {
    el.innerHTML = `<p class="status status-error">${escapeHtmlPos(error.message)}</p>`;
  }
}

document.getElementById('sync-btn').addEventListener('click', async () => {
  const resultEl = document.getElementById('sync-result');
  const btn = document.getElementById('sync-btn');
  btn.disabled = true;
  resultEl.textContent = 'Importing from Heartland...';
  try {
    const response = await staffFetch('/api/pos/sync', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: document.getElementById('sync-from').value, to: document.getElementById('sync-to').value }),
    });
    if (!response.ok) throw new Error(await errorMessage(response, 'Import failed'));
    const status = await response.json();
    resultEl.textContent = `Imported ${status.ordersImported} tickets.`;
    loadOrders();
  } catch (error) {
    resultEl.textContent = error.message;
  } finally {
    loadStatus();
  }
});

document.getElementById('csv-btn').addEventListener('click', async () => {
  const resultEl = document.getElementById('csv-result');
  const file = document.getElementById('csv-file').files[0];
  if (!file) {
    resultEl.textContent = 'Choose a CSV file first.';
    return;
  }
  resultEl.textContent = 'Uploading...';
  try {
    const response = await staffFetch('/api/pos/import-csv', {
      method: 'POST',
      headers: { 'Content-Type': 'text/csv' },
      body: await file.text(),
    });
    if (!response.ok) throw new Error(await errorMessage(response, 'Upload failed'));
    const r = await response.json();
    const columns = Object.entries(r.columns).map(([field, header]) => `${field} ← "${header}"`).join(', ');
    resultEl.innerHTML =
      `Imported ${r.orders} tickets (${r.added} new, ${r.updated} updated) with ${r.items} items.` +
      (r.skippedRows ? ` Skipped ${r.skippedRows} rows missing an item, time, or ticket/table.` : '') +
      `<br>Columns used: ${escapeHtmlPos(columns)}` +
      (r.ignoredColumns.length ? `<br>Ignored: ${escapeHtmlPos(r.ignoredColumns.join(', '))}` : '');
    loadStatus();
    loadOrders();
  } catch (error) {
    resultEl.textContent = error.message;
  }
});

async function loadOrders() {
  const date = document.getElementById('orders-date').value;
  const listEl = document.getElementById('orders-list');
  const summaryEl = document.getElementById('orders-summary');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch(`/api/pos/orders?date=${encodeURIComponent(date)}`);
    if (!response.ok) throw new Error(await errorMessage(response, 'Unable to load tickets'));
    const rows = await response.json();
    const withQR = rows.filter((r) => r.qrVisits > 0).length;
    const offMap = rows.filter((r) => r.table && !r.onFloorMap);
    summaryEl.innerHTML = [
      `<span class="pill pill-approved">${rows.length} tickets</span>`,
      `<span class="pill">${rows.filter((r) => r.table).length} with a table</span>`,
      `<span class="pill">${withQR} matched a QR visit</span>`,
      offMap.length
        ? `<span class="pill pill-warning">${offMap.length} on tables not on the floor map: ${escapeHtmlPos([...new Set(offMap.map((r) => r.table))].join(', '))}</span>`
        : '',
    ].join('');
    if (!rows.length) {
      listEl.innerHTML = '<p class="hint">No tickets imported for this day.</p>';
      return;
    }
    listEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead><tr><th>Ticket</th><th>Table</th><th>Time</th><th>Guests</th><th>Items</th><th>Net</th><th>QR visits</th></tr></thead>
          <tbody>
            ${rows
              .map(
                (r) => `
              <tr>
                <td>${escapeHtmlPos(r.order.ticketNumber || '—')}</td>
                <td>${escapeHtmlPos(r.table || '—')}</td>
                <td>${formatTime(r.order.openedAt)}${r.order.closedAt ? `&ndash;${formatTime(r.order.closedAt)}` : ''}</td>
                <td>${r.order.guestCount ?? '—'}</td>
                <td>${r.order.items.map((i) => `${escapeHtmlPos(i.itemName)}${i.count > 1 ? ` ×${i.count}` : ''}`).join(', ')}</td>
                <td>${r.order.netSales != null ? `$${r.order.netSales.toFixed(2)}` : '—'}</td>
                <td>${r.qrVisits || ''}</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    summaryEl.innerHTML = '';
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlPos(error.message)}</p>`;
  }
}

document.getElementById('sync-from').value = restaurantDate(-2);
document.getElementById('sync-to').value = restaurantDate(-1);
const ordersDate = document.getElementById('orders-date');
ordersDate.value = restaurantDate(-1);
ordersDate.addEventListener('change', loadOrders);
loadStatus();
loadOrders();
