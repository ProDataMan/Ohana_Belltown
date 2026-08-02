function setStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

const amountPicker = document.getElementById('gc-amount-picker');
const customAmountWrap = document.getElementById('gc-custom-amount-wrap');
const customAmountInput = document.getElementById('gc-custom-amount-input');
let selectedAmount = null;

amountPicker.querySelectorAll('.amount-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    amountPicker.querySelectorAll('.amount-btn').forEach((b) => b.classList.remove('selected'));
    btn.classList.add('selected');
    if (btn.dataset.amount === 'custom') {
      customAmountWrap.hidden = false;
      customAmountInput.focus();
      selectedAmount = null;
    } else {
      customAmountWrap.hidden = true;
      selectedAmount = Number(btn.dataset.amount);
    }
  });
});

function renderCheckoutBanner() {
  const params = new URLSearchParams(window.location.search);
  const banner = document.getElementById('gc-checkout-banner');
  if (params.get('checkout') === 'success') {
    banner.textContent = "Thanks! Your gift card is paid for — we'll be in touch shortly using the info you gave us.";
    banner.classList.add('status-ok');
    banner.hidden = false;
    document.getElementById('gc-form-panel').hidden = true;
    return true;
  }
  return false;
}

async function checkAvailability() {
  // Shares Square config with the Shop page's checkout — same
  // "hidden until configured" pattern as AI menu extraction / Apple /
  // Facebook sign-in.
  try {
    const response = await fetch('/api/swag/checkout-status');
    const status = response.ok ? await response.json() : { available: false };
    if (!status.available) {
      document.getElementById('gc-form-panel').innerHTML =
        '<p class="hint">Online gift card purchases aren\'t turned on yet — call us at <a href="tel:+12069569329">(206) 956-9329</a> and we can take care of it over the phone.</p>';
    }
  } catch {
    // Network hiccup — leave the form as-is rather than hide it on a guess.
  }
}

if (!renderCheckoutBanner()) {
  checkAvailability();
}

document.getElementById('gc-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const statusEl = document.getElementById('gc-form-status');
  const submitBtn = document.getElementById('gc-submit-btn');

  const amount = selectedAmount != null ? selectedAmount : Number(customAmountInput.value);
  if (!amount || amount < 5 || amount > 500) {
    setStatus(statusEl, 'Pick or enter an amount between $5 and $500.', true);
    return;
  }
  const buyerName = document.getElementById('gc-buyer-name-input').value.trim();
  const buyerEmail = document.getElementById('gc-buyer-email-input').value.trim();
  if (!buyerName || !buyerEmail) {
    setStatus(statusEl, 'Your name and email are required.', true);
    return;
  }

  submitBtn.disabled = true;
  setStatus(statusEl, 'Starting checkout...', false);

  try {
    const response = await fetch('/api/gift-cards/checkout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        amount,
        buyerName,
        buyerEmail,
        recipientName: document.getElementById('gc-recipient-input').value.trim() || null,
        note: document.getElementById('gc-note-input').value.trim() || null,
      }),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Checkout failed (${response.status}).`);
    }
    const result = await response.json();
    window.location.href = result.checkoutURL;
  } catch (error) {
    setStatus(statusEl, error.message, true);
    submitBtn.disabled = false;
  }
});
