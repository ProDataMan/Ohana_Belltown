function escapeHtmlLoyalty(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setLoyaltyStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

const phoneInput = document.getElementById('phone-input');
const cardStatus = document.getElementById('card-status');
const cardResult = document.getElementById('card-result');

function renderCard(card) {
  cardResult.innerHTML = `
    <div class="loyalty-card-summary">
      <span class="pill ${card.rewardReady ? 'pill-approved' : ''}">${card.punches} / ${card.punchesNeeded} punches</span>
      ${card.rewardReady ? '<span class="pill pill-approved">Free roll ready!</span>' : ''}
      <span class="hint">Total redeemed: ${card.totalRedeemed}</span>
    </div>
  `;
}

async function doLookup() {
  const phone = phoneInput.value.trim();
  if (!phone) return setLoyaltyStatus(cardStatus, 'Enter a phone number first.', true);
  setLoyaltyStatus(cardStatus, 'Looking up...', false);
  try {
    const response = await fetch('/api/loyalty/lookup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone }),
    });
    if (response.status === 404) {
      cardResult.innerHTML = '';
      return setLoyaltyStatus(cardStatus, 'No card found yet — the first punch will create one.', false);
    }
    if (!response.ok) throw new Error(`Lookup failed (${response.status}).`);
    renderCard(await response.json());
    setLoyaltyStatus(cardStatus, '', false);
  } catch (error) {
    setLoyaltyStatus(cardStatus, error.message, true);
  }
}

async function doPunch() {
  const phone = phoneInput.value.trim();
  if (!phone) return setLoyaltyStatus(cardStatus, 'Enter a phone number first.', true);
  setLoyaltyStatus(cardStatus, 'Adding punch...', false);
  try {
    const response = await staffFetch('/api/loyalty/punch', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone }),
    });
    if (!response.ok) throw new Error(`Punch failed (${response.status}).`);
    renderCard(await response.json());
    setLoyaltyStatus(cardStatus, 'Punch added.', false);
  } catch (error) {
    setLoyaltyStatus(cardStatus, error.message, true);
  }
}

async function doRedeem() {
  const phone = phoneInput.value.trim();
  if (!phone) return setLoyaltyStatus(cardStatus, 'Enter a phone number first.', true);
  setLoyaltyStatus(cardStatus, 'Redeeming...', false);
  try {
    const response = await staffFetch('/api/loyalty/redeem', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone }),
    });
    if (!response.ok) throw new Error(`Redeem failed (${response.status}) — this card may not have 10 punches yet.`);
    renderCard(await response.json());
    setLoyaltyStatus(cardStatus, 'Reward redeemed — enjoy the free roll!', false);
  } catch (error) {
    setLoyaltyStatus(cardStatus, error.message, true);
  }
}

document.getElementById('lookup-btn').addEventListener('click', doLookup);
document.getElementById('punch-btn').addEventListener('click', doPunch);
document.getElementById('redeem-btn').addEventListener('click', doRedeem);

const bonusListEl = document.getElementById('bonus-list');

async function loadBonusRequests() {
  bonusListEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/loyalty/bonus-requests');
    if (!response.ok) throw new Error(`Unable to load bonus requests (${response.status}).`);
    const requests = await response.json();
    if (!requests.length) {
      bonusListEl.innerHTML = '<p class="hint">No bonus requests yet.</p>';
      return;
    }
    bonusListEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead>
            <tr><th>Phone</th><th>Type</th><th>Content</th><th>Note</th><th>Status</th><th></th></tr>
          </thead>
          <tbody>
            ${requests
              .map(
                (r) => `
              <tr data-id="${r.id}">
                <td>${escapeHtmlLoyalty(r.phone)}</td>
                <td>${escapeHtmlLoyalty(r.type)}</td>
                <td>${r.type === 'photo'
                  ? `<a href="${escapeHtmlLoyalty(r.content)}" target="_blank" rel="noopener">View photo</a>`
                  : escapeHtmlLoyalty(r.content)}</td>
                <td>${escapeHtmlLoyalty(r.note || '')}</td>
                <td><span class="pill ${r.status === 'approved' ? 'pill-approved' : r.status === 'denied' ? 'pill-denied' : ''}">${r.status}</span></td>
                <td>
                  ${r.status === 'pending'
                    ? `<button type="button" class="approve-btn">Approve</button> <button type="button" class="secondary deny-btn">Deny</button>`
                    : ''}
                </td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
    bonusListEl.querySelectorAll('.approve-btn').forEach((btn) =>
      btn.addEventListener('click', (e) => reviewBonus(e.target.closest('tr').dataset.id, true))
    );
    bonusListEl.querySelectorAll('.deny-btn').forEach((btn) =>
      btn.addEventListener('click', (e) => reviewBonus(e.target.closest('tr').dataset.id, false))
    );
  } catch (error) {
    bonusListEl.innerHTML = `<p class="status status-error">${escapeHtmlLoyalty(error.message)}</p>`;
  }
}

async function reviewBonus(id, approve) {
  try {
    const response = await staffFetch(`/api/loyalty/bonus-requests/${id}/review`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ approve }),
    });
    if (!response.ok) throw new Error(`Review failed (${response.status}).`);
    await loadBonusRequests();
    await loadCustomers();
  } catch (error) {
    bonusListEl.insertAdjacentHTML('afterbegin', `<p class="status status-error">${escapeHtmlLoyalty(error.message)}</p>`);
  }
}

document.getElementById('reload-bonus-btn').addEventListener('click', loadBonusRequests);

const customersListEl = document.getElementById('customers-list');

async function loadCustomers() {
  customersListEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/loyalty/customers');
    if (!response.ok) throw new Error(`Unable to load cards (${response.status}).`);
    const customers = await response.json();
    if (!customers.length) {
      customersListEl.innerHTML = '<p class="hint">No cards yet.</p>';
      return;
    }
    customersListEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead>
            <tr><th>Phone</th><th>Punches</th><th>Redeemed</th><th>Last activity</th></tr>
          </thead>
          <tbody>
            ${customers
              .map(
                (c) => `
              <tr>
                <td>${escapeHtmlLoyalty(c.phone)}</td>
                <td>${c.punches} / 10</td>
                <td>${c.totalRedeemed}</td>
                <td>${new Date(c.updatedAt).toLocaleString()}</td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
  } catch (error) {
    customersListEl.innerHTML = `<p class="status status-error">${escapeHtmlLoyalty(error.message)}</p>`;
  }
}

document.getElementById('reload-customers-btn').addEventListener('click', loadCustomers);

loadBonusRequests();
loadCustomers();
