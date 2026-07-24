function setChangePasswordStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('change-password-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('change-password-status');
  const currentPassword = document.getElementById('current-password-input').value;
  const newPassword = document.getElementById('new-password-input').value;
  const confirmPassword = document.getElementById('confirm-password-input').value;

  if (newPassword !== confirmPassword) {
    return setChangePasswordStatus(statusEl, 'New passwords do not match.', true);
  }

  setChangePasswordStatus(statusEl, 'Saving...', false);
  try {
    const response = await staffFetch('/api/account/change-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ currentPassword, newPassword }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setChangePasswordStatus(statusEl, 'Password changed!', false);
    const params = new URLSearchParams(window.location.search);
    const next = params.get('next') || '/account.html';
    setTimeout(() => {
      window.location.href = next;
    }, 800);
  } catch (error) {
    setChangePasswordStatus(statusEl, error.message, true);
  }
});
