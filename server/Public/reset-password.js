function setResetPasswordStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('reset-password-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('reset-password-status');
  const token = new URLSearchParams(window.location.search).get('token');
  const newPassword = document.getElementById('new-password-input').value;

  if (!token) {
    return setResetPasswordStatus(statusEl, 'This link is missing its token. Request a new one.', true);
  }

  setResetPasswordStatus(statusEl, 'Saving...', false);
  try {
    const response = await fetch('/api/customer/reset-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, newPassword }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setResetPasswordStatus(statusEl, 'Password reset! You can now log in.', false);
    setTimeout(() => {
      window.location.href = '/account-login';
    }, 1200);
  } catch (error) {
    setResetPasswordStatus(statusEl, error.message, true);
  }
});
