function setAccountLoginStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('login-status');
  const email = document.getElementById('email-input').value.trim();
  const password = document.getElementById('password-input').value;

  setAccountLoginStatus(statusEl, 'Logging in...', false);
  try {
    const response = await fetch('/api/customer/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    if (!response.ok) throw new Error('Incorrect email or password.');
    const params = new URLSearchParams(window.location.search);
    window.location.href = params.get('next') || '/my-account.html';
  } catch (error) {
    setAccountLoginStatus(statusEl, error.message, true);
  }
});
