function escapeHtmlAccount(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatMonthDayAccount(monthDay) {
  const [month, day] = monthDay.split('-').map(Number);
  const date = new Date(2000, month - 1, day);
  return date.toLocaleDateString(undefined, { month: 'long', day: 'numeric' });
}

async function loadProfile() {
  const el = document.getElementById('profile-info');
  const oauthEl = document.getElementById('oauth-links');
  try {
    const response = await staffFetch('/api/auth/me');
    if (!response.ok) throw new Error('Unable to load profile.');
    const user = await response.json();
    el.innerHTML = `
      ${user.photoURL ? `<img class="profile-avatar" src="${escapeHtmlAccount(user.photoURL)}" alt="" />` : ''}
      <p><strong>${escapeHtmlAccount(user.displayName)}</strong> (@${escapeHtmlAccount(user.username)})</p>
      <p>Role: <span class="pill ${user.role === 'admin' ? 'pill-approved' : ''}">${escapeHtmlAccount(user.role)}</span></p>
      ${user.email ? `<p>${escapeHtmlAccount(user.email)}</p>` : ''}
      ${user.birthday ? `<p>Birthday: ${escapeHtmlAccount(formatMonthDayAccount(user.birthday))}</p>` : ''}
      ${user.phone ? `<p>Phone: ${escapeHtmlAccount(user.phone)}</p>` : ''}
      ${user.googleLinked || user.appleLinked || user.facebookLinked ? `<p class="hint">Signs in with: ${[user.googleLinked ? 'Google' : null, user.appleLinked ? 'Apple' : null, user.facebookLinked ? 'Facebook' : null].filter(Boolean).join(', ')}</p>` : ''}
    `;
    const emailInput = document.getElementById('email-input');
    if (emailInput) {
      emailInput.value = user.email || '';
    }
    const birthdayInput = document.getElementById('birthday-input');
    if (birthdayInput && user.birthday) {
      // The year is never stored or sent anywhere — 2000 is just a
      // leap-year placeholder so the native date picker has a full date to show.
      birthdayInput.value = `2000-${user.birthday}`;
    }
    const phoneInput = document.getElementById('phone-input');
    if (phoneInput) {
      phoneInput.value = user.phone || '';
    }
    if (oauthEl) {
      oauthEl.innerHTML = `
        ${user.googleLinked
          ? '<span class="pill pill-approved">Google linked</span>'
          : '<a class="oauth-btn oauth-btn-google" href="/auth/google/staff?mode=link">Link Google Account</a>'}
        ${user.appleLinked
          ? '<span class="pill pill-approved">Apple linked</span>'
          : ''}
        ${user.facebookLinked
          ? '<span class="pill pill-approved">Facebook linked</span>'
          : '<a class="oauth-btn oauth-btn-facebook" href="/auth/facebook/staff?mode=link" hidden>Link Facebook Account</a>'}
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

document.getElementById('birthday-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('birthday-status');
  const value = document.getElementById('birthday-input').value;
  if (!value) {
    statusEl.textContent = 'Pick a date first, or use Clear.';
    statusEl.classList.add('status-error');
    return;
  }
  const monthDay = value.slice(5);
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/account/birthday', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ birthday: monthDay }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || 'Unable to save birthday.');
    }
    statusEl.textContent = 'Saved!';
    statusEl.classList.add('status-ok');
    loadProfile();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

document.getElementById('clear-birthday-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('birthday-status');
  statusEl.textContent = 'Clearing...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/account/birthday', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ birthday: null }),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    document.getElementById('birthday-input').value = '';
    statusEl.textContent = 'Cleared.';
    statusEl.classList.add('status-ok');
    loadProfile();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

document.getElementById('phone-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('phone-status');
  const phone = document.getElementById('phone-input').value.trim();
  statusEl.textContent = 'Saving...';
  statusEl.classList.remove('status-error', 'status-ok');
  try {
    const response = await staffFetch('/api/account/phone', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone || null }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || 'Unable to save phone.');
    }
    statusEl.textContent = 'Saved!';
    statusEl.classList.add('status-ok');
    loadProfile();
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
});

loadProfile();
