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
    el.innerHTML = `
      <p><strong>${escapeHtmlMyAccount(customer.displayName)}</strong></p>
      <p>${escapeHtmlMyAccount(customer.email)}</p>
      ${!customer.verified ? '<p class="hint">Check your email to verify your account (a verification link was sent when you signed up).</p>' : ''}
    `;
  } catch (error) {
    el.textContent = error.message;
  }
}

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

loadProfile();
