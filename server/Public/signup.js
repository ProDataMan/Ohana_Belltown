function setSignupStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('signup-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('signup-status');
  const displayName = document.getElementById('name-input').value.trim();
  const email = document.getElementById('email-input').value.trim();
  const password = document.getElementById('password-input').value;

  setSignupStatus(statusEl, 'Creating account...', false);
  try {
    const response = await fetch('/api/customer/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, displayName, password }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    window.location.href = '/my-account.html';
  } catch (error) {
    setSignupStatus(statusEl, error.message, true);
  }
});
