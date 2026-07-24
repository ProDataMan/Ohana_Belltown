function setLoginStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

function nextUrl() {
  const params = new URLSearchParams(window.location.search);
  return params.get('next') || '/edit.html';
}

async function checkSetupNeeded() {
  try {
    const response = await fetch('/api/auth/setup-needed');
    if (!response.ok) return;
    const data = await response.json();
    document.getElementById('login-panel').hidden = data.needsSetup;
    document.getElementById('setup-panel').hidden = !data.needsSetup;
  } catch {
    // default to showing the login form
  }
}

document.getElementById('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('login-status');
  const username = document.getElementById('username-input').value.trim();
  const password = document.getElementById('password-input').value;
  setLoginStatus(statusEl, 'Logging in...', false);
  try {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    if (!response.ok) throw new Error('Incorrect username or password.');
    const user = await response.json();
    if (user.mustChangePassword) {
      window.location.href = '/change-password.html?next=' + encodeURIComponent(nextUrl());
    } else {
      window.location.href = nextUrl();
    }
  } catch (error) {
    setLoginStatus(statusEl, error.message, true);
  }
});

document.getElementById('setup-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('setup-status');
  const displayName = document.getElementById('setup-name-input').value.trim();
  const username = document.getElementById('setup-username-input').value.trim();
  const password = document.getElementById('setup-password-input').value;
  setLoginStatus(statusEl, 'Creating account...', false);
  try {
    const response = await fetch('/api/auth/bootstrap', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, displayName, password }),
    });
    if (!response.ok) throw new Error('Setup failed.');
    window.location.href = nextUrl();
  } catch (error) {
    setLoginStatus(statusEl, error.message, true);
  }
});

checkSetupNeeded();
