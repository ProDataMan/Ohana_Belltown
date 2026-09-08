function setRewardsStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

// --- Punch card: login-gated. A guest sees a log in / create account
// prompt; once logged in, they link a phone number (their card's key);
// once linked, their card status shows automatically. ---
const loyaltyLoggedOutEl = document.getElementById('loyalty-logged-out');
const loyaltyLinkPhoneEl = document.getElementById('loyalty-link-phone');
const loyaltyCardDisplayEl = document.getElementById('loyalty-card-display');
const loyaltyPhoneForm = document.getElementById('loyalty-phone-form');
const loyaltyPhoneInput = document.getElementById('loyalty-phone-input');
const loyaltyPhoneStatus = document.getElementById('loyalty-phone-status');
const loyaltyCardSummary = document.getElementById('loyalty-card-summary');
const changePhoneBtn = document.getElementById('change-phone-btn');

function showLoyaltySection(section) {
  loyaltyLoggedOutEl.hidden = section !== 'logged-out';
  loyaltyLinkPhoneEl.hidden = section !== 'link-phone';
  loyaltyCardDisplayEl.hidden = section !== 'card';
}

// Once we know the guest's linked phone, prefill it into the referral/bonus
// forms below so a logged-in guest doesn't have to type it a second time —
// those forms still work standalone for anyone not logged in.
function prefillPhoneFields(phone) {
  const referralPhoneInput = document.getElementById('referral-phone-input');
  const bonusPhoneInput = document.getElementById('bonus-phone-input');
  if (referralPhoneInput && !referralPhoneInput.value) referralPhoneInput.value = phone;
  if (bonusPhoneInput && !bonusPhoneInput.value) bonusPhoneInput.value = phone;
}

async function loadPunchCard() {
  const meResponse = await fetch('/api/customer/me');
  if (meResponse.status === 401) {
    showLoyaltySection('logged-out');
    return;
  }
  if (!meResponse.ok) return;

  const loyaltyResponse = await fetch('/api/customer/loyalty');
  if (!loyaltyResponse.ok) return;
  const loyalty = await loyaltyResponse.json();

  if (!loyalty.linkedPhone) {
    showLoyaltySection('link-phone');
    return;
  }

  prefillPhoneFields(loyalty.linkedPhone);
  if (loyalty.status) {
    loyaltyCardSummary.innerHTML = `
      <div class="loyalty-card-summary">
        <span class="pill ${loyalty.status.rewardReady ? 'pill-approved' : ''}">${loyalty.status.punches} / ${loyalty.status.punchesNeeded} punches</span>
        ${loyalty.status.bonusPoints > 0 ? `<span class="pill">+${loyalty.status.bonusPoints}/10 toward your next punch from shares</span>` : ''}
        ${loyalty.status.rewardReady ? '<span class="pill pill-approved">Free roll ready — show this to your server!</span>' : ''}
      </div>
    `;
  } else {
    loyaltyCardSummary.innerHTML = `<p class="hint">Card linked to ${loyalty.linkedPhone} &mdash; no punches yet. Order sushi to start earning!</p>`;
  }
  showLoyaltySection('card');
}

loyaltyPhoneForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const phone = loyaltyPhoneInput.value.trim();
  if (!phone) return setRewardsStatus(loyaltyPhoneStatus, 'Enter your phone number first.', true);
  setRewardsStatus(loyaltyPhoneStatus, 'Saving...', false);
  try {
    const response = await fetch('/api/customer/loyalty-phone', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Failed (${response.status}).`);
    }
    setRewardsStatus(loyaltyPhoneStatus, '', false);
    await loadPunchCard();
  } catch (error) {
    setRewardsStatus(loyaltyPhoneStatus, error.message, true);
  }
});

changePhoneBtn.addEventListener('click', () => {
  showLoyaltySection('link-phone');
});

loadPunchCard();

document.getElementById('referral-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('referral-status');
  const phone = document.getElementById('referral-phone-input').value.trim();
  const referrerPhone = document.getElementById('referral-referrer-input').value.trim();
  if (!phone || !referrerPhone) return setRewardsStatus(statusEl, 'Enter both phone numbers first.', true);

  setRewardsStatus(statusEl, 'Submitting...', false);
  try {
    const response = await fetch('/api/loyalty/referral', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone, referrerPhone }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Submission failed (${response.status}).`);
    }
    setRewardsStatus(statusEl, "Got it! You'll both get a bonus punch once you earn your first one.", false);
    event.target.reset();
  } catch (error) {
    setRewardsStatus(statusEl, error.message, true);
  }
});

const typeRadios = document.querySelectorAll('input[name="bonus-type"]');
const photoLabel = document.getElementById('bonus-photo-label');
const socialLabel = document.getElementById('bonus-social-label');
const menuItemHint = document.getElementById('bonus-menu-item-hint');

typeRadios.forEach((radio) => {
  radio.addEventListener('change', () => {
    const isPhoto = document.querySelector('input[name="bonus-type"]:checked').value === 'photo';
    photoLabel.hidden = !isPhoto;
    socialLabel.hidden = isPhoto;
    menuItemHint.textContent = isPhoto ? '(required for a photo)' : '(optional)';
  });
});

// A dish picker with real search, since there are ~250 menu items — a
// <datalist> gives free substring-filtered autocomplete without a custom
// dropdown widget. Keeps a name->id map since the datalist itself can only
// carry display text, not the id the backend actually needs.
const menuItemInput = document.getElementById('bonus-menu-item-input');
const menuItemOptionsEl = document.getElementById('bonus-menu-item-options');
let menuItemsByName = {};

async function loadMenuItemsForPicker() {
  try {
    const response = await fetch('/api/menu');
    if (!response.ok) return;
    const menu = await response.json();
    (menu.categories || []).forEach((category) => {
      (category.items || []).forEach((item) => {
        menuItemsByName[item.name] = item.id;
      });
    });
    menuItemOptionsEl.innerHTML = Object.keys(menuItemsByName)
      .sort((a, b) => a.localeCompare(b))
      .map((name) => `<option value="${name.replaceAll('"', '&quot;')}"></option>`)
      .join('');
  } catch {
    // The picker just won't offer suggestions — submission still validates
    // against whatever was typed, which will simply fail to match anything.
  }
}
loadMenuItemsForPicker();

function selectedMenuItem() {
  const typed = menuItemInput.value.trim();
  const id = menuItemsByName[typed];
  return id ? { id, name: typed } : null;
}

document.getElementById('bonus-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('bonus-status');
  const phone = document.getElementById('bonus-phone-input').value.trim();
  const type = document.querySelector('input[name="bonus-type"]:checked').value;
  const note = document.getElementById('bonus-note-input').value.trim() || null;

  if (!phone) return setRewardsStatus(statusEl, 'Enter your phone number first.', true);

  const menuItem = selectedMenuItem();
  if (type === 'photo' && !menuItem) {
    return setRewardsStatus(statusEl, 'Please select which dish this photo is of, from the list.', true);
  }

  setRewardsStatus(statusEl, 'Submitting...', false);
  try {
    let content;
    if (type === 'photo') {
      const file = document.getElementById('bonus-photo-input').files[0];
      if (!file) return setRewardsStatus(statusEl, 'Choose a photo to share.', true);
      const formData = new FormData();
      formData.append('image', file);
      const uploadResponse = await fetch('/api/upload', { method: 'POST', body: formData });
      if (!uploadResponse.ok) {
        const uploadBody = await uploadResponse.json().catch(() => ({}));
        throw new Error(uploadBody.reason || `Photo upload failed (${uploadResponse.status}).`);
      }
      const uploadResult = await uploadResponse.json();
      content = uploadResult.url;
    } else {
      content = document.getElementById('bonus-social-input').value.trim();
      if (!content) return setRewardsStatus(statusEl, 'Add a link or your @handle.', true);
    }

    const response = await fetch('/api/loyalty/bonus-request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone,
        type,
        content,
        note,
        menuItemId: menuItem ? menuItem.id : null,
        menuItemName: menuItem ? menuItem.name : null,
      }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Submission failed (${response.status}).`);
    }
    setRewardsStatus(
      statusEl,
      type === 'photo'
        ? "Thanks! Once approved, your photo joins that dish's gallery — approved shares are worth 1/10 of a punch, up to 2 per visit."
        : "Thanks! We'll review it soon — approved shares are worth 1/10 of a punch, up to 2 per visit.",
      false
    );
    event.target.reset();
    photoLabel.hidden = false;
    socialLabel.hidden = true;
    menuItemHint.textContent = '(required for a photo)';
  } catch (error) {
    setRewardsStatus(statusEl, error.message, true);
  }
});
