function setWaitlistStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

document.getElementById('waitlist-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('waitlist-status');
  const name = document.getElementById('waitlist-name-input').value.trim();
  const phone = document.getElementById('waitlist-phone-input').value.trim();
  const partySize = Number.parseInt(document.getElementById('waitlist-party-input').value, 10);
  const note = document.getElementById('waitlist-note-input').value.trim() || null;

  if (!name || !phone) return setWaitlistStatus(statusEl, 'Name and phone number are required.', true);

  setWaitlistStatus(statusEl, 'Adding you to the list...', false);
  try {
    const response = await fetch('/api/waitlist/join', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, phone, partySize, note }),
    });
    if (!response.ok) throw new Error(`Something went wrong (${response.status}). Please try again.`);
    setWaitlistStatus(statusEl, "You're on the list! We'll text you when your table's ready.", false);
    event.target.reset();
    document.getElementById('waitlist-party-input').value = 2;
  } catch (error) {
    setWaitlistStatus(statusEl, error.message, true);
  }
});
