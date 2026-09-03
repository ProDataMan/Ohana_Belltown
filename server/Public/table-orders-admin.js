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

// Shared by both queues below — a server talked to the table and they no
// longer want this item, whether it's still waiting to be entered or
// already cooking. Asks for an optional reason (kitchen out of it, guest
// changed their mind, etc.) for the record, but a blank answer still cancels.
function wireCancelButtons(container) {
  container.querySelectorAll('.cancel-btn').forEach((btn) => {
    btn.addEventListener('click', async (event) => {
      const row = event.target.closest('tr');
      const id = row.dataset.id;
      const itemName = row.dataset.itemName;
      if (!confirm(`Cancel "${itemName}"? This can't be undone.`)) return;
      const reason = prompt('Reason (optional):') || null;
      const response = await staffFetch(`/api/table-orders/${id}/cancel`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ reason }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        alert(body.reason || `Failed to cancel (${response.status}).`);
        return;
      }
      await loadTableOrders();
    });
  });
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
            <tr data-id="${o.id}" data-item-name="${escapeHtmlTableOrders(o.itemName)}">
              <td><span class="pill pill-approved">Table ${escapeHtmlTableOrders(o.tableId)}</span></td>
              <td>${itemDisplayName(o)}</td>
              <td>${minutesAgoTableOrder(o.createdAt)}</td>
              <td>
                <button type="button" class="secondary enter-btn">Confirm Entered</button>
                <button type="button" class="secondary cancel-btn">Cancel</button>
              </td>
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
  wireCancelButtons(needsEntryEl);
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
              <tr data-id="${o.id}" data-item-name="${escapeHtmlTableOrders(o.itemName)}">
                <td><span class="pill pill-approved">Table ${escapeHtmlTableOrders(o.tableId)}</span></td>
                <td>${escapeHtmlTableOrders(o.itemName)}</td>
                <td>${minutesAgoTableOrder(o.enteredAt || o.createdAt)}</td>
                <td>${isReady ? '<span class="pill pill-warning">Ready now</span>' : '<span class="pill">Cooking</span>'}</td>
                <td>
                  <button type="button" class="secondary deliver-btn">Confirm Delivered</button>
                  <button type="button" class="secondary cancel-btn">Cancel</button>
                </td>
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
  wireCancelButtons(awaitingDeliveryEl);
}

async function loadTableOrders() {
  try {
    const response = await staffFetch('/api/table-orders/dashboard');
    if (!response.ok) throw new Error(`Unable to load table orders (${response.status}).`);
    const data = await response.json();
    renderNeedsEntry(data.needsEntry);
    renderAwaitingDelivery(data.awaitingDelivery);
    updateFloorMapFlashing(data.needsEntry, data.awaitingDelivery);
  } catch (error) {
    const message = `<p class="status status-error">${escapeHtmlTableOrders(error.message)}</p>`;
    needsEntryEl.innerHTML = message;
    awaitingDeliveryEl.innerHTML = message;
  }
}

// --- Floor map ---

const sectionLabels = { dining: 'Dining', bar: 'Bar', sushi: 'Sushi', deck: 'Deck' };
const sectionOrder = ['dining', 'bar', 'sushi', 'deck'];
let floorMapEntries = [];
// A link (e.g. the site-wide "N table orders" alert) can jump straight to the
// section that needs attention via ?section=deck instead of always landing on Dining.
const requestedFloorMapSection = new URLSearchParams(window.location.search).get('section');
let activeFloorMapSection = sectionOrder.includes(requestedFloorMapSection) ? requestedFloorMapSection : 'dining';

function renderFloorMapCanvas() {
  const canvas = document.getElementById('floor-map-canvas');
  const tables = floorMapEntries.filter((entry) => entry.section === activeFloorMapSection);
  canvas.innerHTML = tables
    .map(
      (entry) => `
        <div
          class="floor-map-table shape-${entry.shape}"
          data-table-id="${escapeHtmlTableOrders(entry.id)}"
          style="left: ${entry.x}%; top: ${entry.y}%;"
        >${escapeHtmlTableOrders(entry.id)}</div>
      `
    )
    .join('');
}

function renderFloorMapTabs() {
  const tabsEl = document.getElementById('floor-map-tabs');
  const present = sectionOrder.filter((s) => floorMapEntries.some((e) => e.section === s));
  tabsEl.innerHTML = present
    .map(
      (s) => `<button type="button" data-section="${s}" class="${s === activeFloorMapSection ? 'active' : ''}">${sectionLabels[s] || s}</button>`
    )
    .join('');
  tabsEl.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      activeFloorMapSection = btn.dataset.section;
      tabsEl.querySelectorAll('button').forEach((b) => b.classList.toggle('active', b === btn));
      renderFloorMapCanvas();
      loadTableOrders();
    });
  });
}

// A table shouldn't start flashing for delivery the instant an order is
// entered — that's before the kitchen could plausibly have it ready. It
// becomes eligible once we're at whichever is greater: the average prep time
// of the single slowest dish still cooking there (the table can't be fully
// ready before that dish alone would be), or half the combined average prep
// time of everything cooking there (several dishes cooking in parallel is a
// different wait than one dish taking three times as long).
function tablesEligibleForAwaitingFlash(awaitingDelivery) {
  const byTable = {};
  awaitingDelivery.forEach((o) => {
    (byTable[o.tableId] = byTable[o.tableId] || []).push(o);
  });

  const eligible = new Set();
  Object.entries(byTable).forEach(([tableId, orders]) => {
    const durationsMs = [];
    const enteredTimesMs = [];
    orders.forEach((o) => {
      if (!o.enteredAt || !o.estimatedReadyAt) return;
      const entered = new Date(o.enteredAt).getTime();
      const ready = new Date(o.estimatedReadyAt).getTime();
      durationsMs.push(ready - entered);
      enteredTimesMs.push(entered);
    });
    if (!durationsMs.length) return;

    const longestDishMs = Math.max(...durationsMs);
    const halfOfTotalPrepMs = durationsMs.reduce((sum, d) => sum + d, 0) / 2;
    const delayMs = Math.max(longestDishMs, halfOfTotalPrepMs);
    const earliestEnteredMs = Math.min(...enteredTimesMs);
    if (Date.now() - earliestEnteredMs >= delayMs) {
      eligible.add(tableId);
    }
  });
  return eligible;
}

function updateFloorMapFlashing(needsEntry, awaitingDelivery) {
  const needsIds = new Set(needsEntry.map((o) => o.tableId));
  const allAwaitingIds = new Set(awaitingDelivery.map((o) => o.tableId));
  const eligibleAwaitingIds = tablesEligibleForAwaitingFlash(awaitingDelivery);
  document.querySelectorAll('.floor-map-table').forEach((el) => {
    const id = el.dataset.tableId;
    el.classList.toggle('flash-needs', needsIds.has(id));
    el.classList.toggle('flash-awaiting', !needsIds.has(id) && eligibleAwaitingIds.has(id));
    // Entered but not yet plausibly ready — a static color (not flashing)
    // just to show an order's been placed and is being worked on.
    el.classList.toggle('processing', !needsIds.has(id) && allAwaitingIds.has(id) && !eligibleAwaitingIds.has(id));
  });

  // A table in a section other than the one currently shown can't flash on
  // the canvas (it isn't rendered), so flash that section's tab instead.
  const tableSection = {};
  floorMapEntries.forEach((entry) => {
    tableSection[entry.id] = entry.section;
  });
  const sectionsWithNeeds = new Set(needsEntry.map((o) => tableSection[o.tableId]).filter(Boolean));
  const sectionsWithAwaiting = new Set([...eligibleAwaitingIds].map((tableId) => tableSection[tableId]).filter(Boolean));
  document.querySelectorAll('#floor-map-tabs button').forEach((btn) => {
    const section = btn.dataset.section;
    if (section === activeFloorMapSection) {
      btn.classList.remove('tab-flash-needs', 'tab-flash-awaiting');
      return;
    }
    btn.classList.toggle('tab-flash-needs', sectionsWithNeeds.has(section));
    btn.classList.toggle('tab-flash-awaiting', !sectionsWithNeeds.has(section) && sectionsWithAwaiting.has(section));
  });
}

async function loadFloorMap() {
  try {
    const response = await fetch('/api/table-map');
    if (!response.ok) throw new Error(`Unable to load the floor map (${response.status}).`);
    floorMapEntries = await response.json();
    renderFloorMapTabs();
    renderFloorMapCanvas();
  } catch (error) {
    document.getElementById('floor-map-canvas').innerHTML = `<p class="status status-error">${escapeHtmlTableOrders(error.message)}</p>`;
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
loadFloorMap().then(loadTableOrders);
setInterval(loadTableOrders, 15000);
