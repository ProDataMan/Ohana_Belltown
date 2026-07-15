function setRewardsStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

const checkPhoneInput = document.getElementById('check-phone-input');
const checkStatus = document.getElementById('check-status');
const checkResult = document.getElementById('check-result');

document.getElementById('check-btn').addEventListener('click', async () => {
  const phone = checkPhoneInput.value.trim();
  if (!phone) return setRewardsStatus(checkStatus, 'Enter your phone number first.', true);
  setRewardsStatus(checkStatus, 'Checking...', false);
  checkResult.innerHTML = '';
  try {
    const response = await fetch('/api/loyalty/lookup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone }),
    });
    if (response.status === 404) {
      return setRewardsStatus(checkStatus, "No card yet — ask staff to start one on your next sushi order.", false);
    }
    if (!response.ok) throw new Error('Something went wrong. Please try again.');
    const card = await response.json();
    setRewardsStatus(checkStatus, '', false);
    checkResult.innerHTML = `
      <div class="loyalty-card-summary">
        <span class="pill ${card.rewardReady ? 'pill-approved' : ''}">${card.punches} / ${card.punchesNeeded} punches</span>
        ${card.rewardReady ? '<span class="pill pill-approved">Free roll ready — show this to your server!</span>' : ''}
      </div>
    `;
  } catch (error) {
    setRewardsStatus(checkStatus, error.message, true);
  }
});

const typeRadios = document.querySelectorAll('input[name="bonus-type"]');
const photoLabel = document.getElementById('bonus-photo-label');
const socialLabel = document.getElementById('bonus-social-label');

typeRadios.forEach((radio) => {
  radio.addEventListener('change', () => {
    const isPhoto = document.querySelector('input[name="bonus-type"]:checked').value === 'photo';
    photoLabel.hidden = !isPhoto;
    socialLabel.hidden = isPhoto;
  });
});

document.getElementById('bonus-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('bonus-status');
  const phone = document.getElementById('bonus-phone-input').value.trim();
  const type = document.querySelector('input[name="bonus-type"]:checked').value;
  const note = document.getElementById('bonus-note-input').value.trim() || null;

  if (!phone) return setRewardsStatus(statusEl, 'Enter your phone number first.', true);

  setRewardsStatus(statusEl, 'Submitting...', false);
  try {
    let content;
    if (type === 'photo') {
      const file = document.getElementById('bonus-photo-input').files[0];
      if (!file) return setRewardsStatus(statusEl, 'Choose a photo to share.', true);
      const formData = new FormData();
      formData.append('image', file);
      const uploadResponse = await fetch('/api/upload', { method: 'POST', body: formData });
      if (!uploadResponse.ok) throw new Error(`Photo upload failed (${uploadResponse.status}).`);
      const uploadResult = await uploadResponse.json();
      content = uploadResult.url;
    } else {
      content = document.getElementById('bonus-social-input').value.trim();
      if (!content) return setRewardsStatus(statusEl, 'Add a link or your @handle.', true);
    }

    const response = await fetch('/api/loyalty/bonus-request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone, type, content, note }),
    });
    if (!response.ok) throw new Error(`Submission failed (${response.status}).`);
    setRewardsStatus(statusEl, "Thanks! We'll review it and add your bonus punch soon.", false);
    event.target.reset();
    photoLabel.hidden = false;
    socialLabel.hidden = true;
  } catch (error) {
    setRewardsStatus(statusEl, error.message, true);
  }
});
