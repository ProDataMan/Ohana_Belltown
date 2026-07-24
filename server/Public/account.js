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

loadProfile();
