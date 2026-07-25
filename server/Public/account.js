function escapeHtmlAccount(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadProfile() {
  const el = document.getElementById('profile-info');
  const oauthEl = document.getElementById('oauth-links');
  try {
    const response = await staffFetch('/api/auth/me');
    if (!response.ok) throw new Error('Unable to load profile.');
    const user = await response.json();
    el.innerHTML = `
      <p><strong>${escapeHtmlAccount(user.displayName)}</strong> (@${escapeHtmlAccount(user.username)})</p>
      <p>Role: <span class="pill ${user.role === 'admin' ? 'pill-approved' : ''}">${escapeHtmlAccount(user.role)}</span></p>
    `;
    const emailInput = document.getElementById('email-input');
    if (emailInput) {
      emailInput.value = user.email || '';
    }
    if (oauthEl) {
      oauthEl.innerHTML = `
        ${user.googleLinked
          ? '<span class="pill pill-approved">Google linked</span>'
          : '<a class="oauth-btn oauth-btn-google" href="/auth/google/staff?mode=link">Link Google Account</a>'}
        ${user.appleLinked
          ? '<span class="pill pill-approved">Apple linked</span>'
          : '<a class="oauth-btn oauth-btn-apple" href="/auth/apple/staff?mode=link">Link Apple Account</a>'}
      `;
    }
  } catch (error) {
    el.textContent = error.message;
  }
}

document.getElementById('logout-btn').addEventListener('click', async () => {
  await fetch('/api/auth/logout', { method: 'POST' });
  window.location.href = '/login';
});

document.getElementById('email-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('email-status');
  const email = document.getElementById('email-input').value.trim();
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/account/email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email || null }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || 'Unable to save email.');
    }
    statusEl.textContent = 'Saved!';
    statusEl.classList.add('status-ok');
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

loadProfile();
