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
  try {
    const response = await staffFetch('/api/auth/me');
    if (!response.ok) throw new Error('Unable to load profile.');
    const user = await response.json();
    el.innerHTML = `
      <p><strong>${escapeHtmlAccount(user.displayName)}</strong> (@${escapeHtmlAccount(user.username)})</p>
      <p>Role: <span class="pill ${user.role === 'admin' ? 'pill-approved' : ''}">${escapeHtmlAccount(user.role)}</span></p>
    `;
  } catch (error) {
    el.textContent = error.message;
  }
}

document.getElementById('logout-btn').addEventListener('click', async () => {
  await fetch('/api/auth/logout', { method: 'POST' });
  window.location.href = '/login';
});

loadProfile();
