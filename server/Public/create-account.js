function setCreateAccountStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('create-account-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('create-account-status');
  const displayName = document.getElementById('display-name-input').value.trim();
  const username = document.getElementById('username-input').value.trim();
  const password = document.getElementById('password-input').value;
  const role = document.querySelector('input[name="role"]:checked').value;

  setCreateAccountStatus(statusEl, 'Creating...', false);
  try {
    const response = await staffFetch('/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ displayName, username, password, role }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setCreateAccountStatus(statusEl, `Account created for ${displayName}.`, false);
    event.target.reset();
  } catch (error) {
    setCreateAccountStatus(statusEl, error.message, true);
  }
});
