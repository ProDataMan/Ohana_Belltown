function setForgotPasswordStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('forgot-password-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('forgot-password-status');
  const email = document.getElementById('email-input').value.trim();

  setForgotPasswordStatus(statusEl, 'Sending...', false);
  try {
    const response = await fetch('/api/customer/forgot-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
    });
    if (!response.ok) throw new Error('Something went wrong. Please try again.');
    setForgotPasswordStatus(
      statusEl,
      "If that email has an account, we've sent a reset link. It expires in 1 hour.",
      false
    );
    event.target.reset();
  } catch (error) {
    setForgotPasswordStatus(statusEl, error.message, true);
  }
});
