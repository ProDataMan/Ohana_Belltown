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

// Once we know the guest's linked phone, prefill it into the bonus-punch
// form below so a logged-in guest doesn't have to type it a second time —
// that form still works standalone for anyone not logged in. The referral
// form is handled separately (see showReferralSection below) since it only
// works for a phone that's never punched before — pre-filling an existing
// customer's own number into it would just guarantee a rejection.
function prefillPhoneFields(phone) {
  const bonusPhoneInput = document.getElementById('bonus-phone-input');
  if (bonusPhoneInput && !bonusPhoneInput.value) bonusPhoneInput.value = phone;
}

const referralExistingCardEl = document.getElementById('referral-existing-card');
const referralNewCustomerEl = document.getElementById('referral-new-customer');
const referralShareLinkInput = document.getElementById('referral-share-link');

// A customer who already has a card (linked phone) can't use the "Refer a
// Friend" form for themselves — LoyaltyStore.setReferrer only accepts a
// phone that's never punched before, so submitting their own number always
// fails. Swap the form for a shareable link instead, which pre-fills
// "Referred by" for whoever actually is new (see the ?ref= handling below).
function showReferralSection(linkedPhone) {
  if (linkedPhone) {
    referralNewCustomerEl.hidden = true;
    referralExistingCardEl.hidden = false;
    const url = new URL('/rewards', window.location.origin);
    url.searchParams.set('ref', linkedPhone);
    referralShareLinkInput.value = url.toString();
  } else {
    referralExistingCardEl.hidden = true;
    referralNewCustomerEl.hidden = false;
  }
}

// A friend arriving via a shared referral link (?ref=<phone>) shouldn't have
// to know or type the referrer's number — works regardless of whether this
// visitor ends up logging in, since the referral form itself doesn't
// require it.
const refParam = new URLSearchParams(window.location.search).get('ref');
if (refParam) {
  const referrerInput = document.getElementById('referral-referrer-input');
  if (referrerInput) referrerInput.value = refParam;
}

document.getElementById('copy-referral-link-btn').addEventListener('click', async () => {
  const statusEl = document.getElementById('referral-copy-status');
  try {
    await navigator.clipboard.writeText(referralShareLinkInput.value);
    setRewardsStatus(statusEl, 'Copied!', false);
  } catch {
    referralShareLinkInput.select();
    setRewardsStatus(statusEl, 'Select and copy the link above.', false);
  }
});

async function loadPunchCard() {
  const meResponse = await fetch('/api/customer/me');
  if (meResponse.status === 401) {
    showLoyaltySection('logged-out');
    showReferralSection(null);
    return;
  }
  if (!meResponse.ok) return;

  const loyaltyResponse = await fetch('/api/customer/loyalty');
  if (!loyaltyResponse.ok) return;
  const loyalty = await loyaltyResponse.json();

  if (!loyalty.linkedPhone) {
    showLoyaltySection('link-phone');
    showReferralSection(null);
    return;
  }

  prefillPhoneFields(loyalty.linkedPhone);
  renderPunchCardInto(loyaltyCardSummary, loyalty.status);
  showLoyaltySection('card');
  showReferralSection(loyalty.linkedPhone);
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

// States the real redemption cap in the "How It Works" copy instead of a
// hardcoded number, so raising or lowering it from the admin side (see
// loyalty-admin.js) doesn't leave stale copy on this page.
(async () => {
  try {
    const response = await fetch('/api/loyalty/redemption-cap');
    if (!response.ok) return;
    const { maxRedemptionPrice } = await response.json();
    const capCopyEl = document.getElementById('redemption-cap-copy');
    if (capCopyEl) capCopyEl.textContent = `$${maxRedemptionPrice.toFixed(0)} and under`;
  } catch {
    // Copy just keeps its default placeholder amount.
  }
})();

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
