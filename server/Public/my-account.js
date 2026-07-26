function escapeHtmlMyAccount(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setMyAccountStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

function formatMonthDayMyAccount(monthDay) {
  const [month, day] = monthDay.split('-').map(Number);
  const date = new Date(2000, month - 1, day);
  return date.toLocaleDateString(undefined, { month: 'long', day: 'numeric' });
}

async function loadProfile() {
  const el = document.getElementById('profile-info');
  try {
    const response = await fetch('/api/customer/me');
    if (response.status === 401) {
      window.location.href = '/account-login?next=/my-account.html';
      return;
    }
    if (!response.ok) throw new Error('Unable to load profile.');
    const customer = await response.json();

    const signInMethods = [];
    if (customer.googleLinked) signInMethods.push('Google');
    if (customer.appleLinked) signInMethods.push('Apple');
    if (customer.facebookLinked) signInMethods.push('Facebook');
    if (customer.hasPassword) signInMethods.push('Password');

    el.innerHTML = `
      ${customer.photoURL ? `<img class="profile-avatar" src="${escapeHtmlMyAccount(customer.photoURL)}" alt="" />` : ''}
      <p><strong>${escapeHtmlMyAccount(customer.displayName)}</strong></p>
      <p>${escapeHtmlMyAccount(customer.email)}${customer.verified ? '' : ' (unverified)'}</p>
      ${customer.birthday ? `<p>Birthday: ${escapeHtmlMyAccount(formatMonthDayMyAccount(customer.birthday))}</p>` : ''}
      ${customer.loyaltyPhone ? `<p>Phone (Rewards): ${escapeHtmlMyAccount(customer.loyaltyPhone)}</p>` : ''}
      ${signInMethods.length ? `<p class="hint">Signs in with: ${escapeHtmlMyAccount(signInMethods.join(', '))}</p>` : ''}
      ${!customer.verified ? '<p class="hint">Check your email to verify your account (a verification link was sent when you signed up).</p>' : ''}
    `;
    const birthdayInput = document.getElementById('birthday-input');
    if (birthdayInput && customer.birthday) {
      // The year is never stored or sent anywhere — 2000 is just a
      // leap-year placeholder so the native date picker has a full date to show.
      birthdayInput.value = `2000-${customer.birthday}`;
    }
  } catch (error) {
    el.textContent = error.message;
  }
}

async function loadLoyalty() {
  const el = document.getElementById('loyalty-info');
  const phoneInput = document.getElementById('loyalty-phone-input');
  try {
    const response = await fetch('/api/customer/loyalty');
    if (!response.ok) throw new Error('Unable to load rewards status.');
    const data = await response.json();
    if (!data.linkedPhone) {
      el.textContent = 'No phone number linked yet.';
      return;
    }
    phoneInput.value = data.linkedPhone;
    if (data.status) {
      el.innerHTML = `
        <div class="loyalty-card-summary">
          <span class="pill pill-approved">${data.status.punches} / ${data.status.punchesNeeded} punches</span>
          ${data.status.rewardReady ? '<span class="pill pill-approved">Reward ready!</span>' : ''}
          <span class="pill">${data.status.totalRedeemed} redeemed all-time</span>
        </div>
      `;
    } else {
      el.textContent = `Linked to ${data.linkedPhone} — no punches yet.`;
    }
  } catch (error) {
    el.textContent = error.message;
  }
}

document.getElementById('loyalty-phone-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('loyalty-phone-status');
  const phone = document.getElementById('loyalty-phone-input').value.trim();
  if (!phone) return setMyAccountStatus(statusEl, 'Enter a phone number first.', true);

  setMyAccountStatus(statusEl, 'Linking...', false);
  try {
    const response = await fetch('/api/customer/loyalty-phone', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setMyAccountStatus(statusEl, 'Linked!', false);
    loadLoyalty();
  } catch (error) {
    setMyAccountStatus(statusEl, error.message, true);
  }
});

document.getElementById('unlink-loyalty-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('loyalty-phone-status');
  setMyAccountStatus(statusEl, 'Unlinking...', false);
  try {
    const response = await fetch('/api/customer/loyalty-phone', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: null }),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    document.getElementById('loyalty-phone-input').value = '';
    setMyAccountStatus(statusEl, 'Unlinked.', false);
    loadLoyalty();
  } catch (error) {
    setMyAccountStatus(statusEl, error.message, true);
  }
});

if (new URLSearchParams(window.location.search).get('verified') === '1') {
  document.getElementById('verified-banner').hidden = false;
}

document.getElementById('logout-btn').addEventListener('click', async () => {
  await fetch('/api/customer/logout', { method: 'POST' });
  window.location.href = '/';
});

document.getElementById('change-password-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('change-password-status');
  const currentPassword = document.getElementById('current-password-input').value;
  const newPassword = document.getElementById('new-password-input').value;

  setMyAccountStatus(statusEl, 'Saving...', false);
  try {
    const response = await fetch('/api/customer/change-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ currentPassword, newPassword }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setMyAccountStatus(statusEl, 'Password changed!', false);
    event.target.reset();
  } catch (error) {
    setMyAccountStatus(statusEl, error.message, true);
  }
});

document.getElementById('birthday-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('birthday-status');
  const value = document.getElementById('birthday-input').value;
  if (!value) return setMyAccountStatus(statusEl, 'Pick a date first, or use Clear.', true);
  const monthDay = value.slice(5);

  setMyAccountStatus(statusEl, 'Saving...', false);
  try {
    const response = await fetch('/api/customer/birthday', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ birthday: monthDay }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setMyAccountStatus(statusEl, 'Saved!', false);
  } catch (error) {
    setMyAccountStatus(statusEl, error.message, true);
  }
});

document.getElementById('clear-birthday-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('birthday-status');
  setMyAccountStatus(statusEl, 'Clearing...', false);
  try {
    const response = await fetch('/api/customer/birthday', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ birthday: null }),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    document.getElementById('birthday-input').value = '';
    setMyAccountStatus(statusEl, 'Cleared.', false);
  } catch (error) {
    setMyAccountStatus(statusEl, error.message, true);
  }
});

document.getElementById('deactivate-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('deactivate-status');
  if (!window.confirm('Deactivate your account? You will be signed out and unable to log in until we restore it.')) {
    return;
  }
  setMyAccountStatus(statusEl, 'Deactivating...', false);
  try {
    const response = await fetch('/api/customer/deactivate', { method: 'POST' });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    window.location.href = '/';
  } catch (error) {
    setMyAccountStatus(statusEl, error.message, true);
  }
});

function orderStatusLabel(order) {
  if (order.status === 'delivered') return 'Delivered';
  if (order.status === 'entered') return 'Being prepared';
  return 'Sent to staff';
}

async function loadOrderHistory() {
  const el = document.getElementById('order-history-list');
  el.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await fetch('/api/customer/order-history');
    if (!response.ok) throw new Error(`Unable to load order history (${response.status}).`);
    const orders = await response.json();
    if (!orders.length) {
      el.innerHTML = '<p class="hint">No table orders yet.</p>';
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
                <td>${escapeHtmlMyAccount(o.itemName)}</td>
                <td>${escapeHtmlMyAccount(o.tableId)}</td>
                <td><span class="pill ${o.status === 'delivered' ? 'pill-approved' : ''}">${orderStatusLabel(o)}</span></td>
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
    el.innerHTML = `<p class="status status-error">${escapeHtmlMyAccount(error.message)}</p>`;
  }
}

document.getElementById('reload-order-history-btn').addEventListener('click', loadOrderHistory);

loadProfile();
loadLoyalty();
loadOrderHistory();
