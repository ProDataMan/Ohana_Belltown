document.getElementById('nav-toggle')?.addEventListener('click', () => {
  document.getElementById('site-nav')?.classList.toggle('open');
});

document.querySelectorAll('.nav-dropdown-toggle').forEach((btn) => {
  btn.addEventListener('click', () => {
    const dropdown = btn.parentElement;
    const willOpen = !dropdown?.classList.contains('open');
    document.querySelectorAll('.nav-dropdown.open').forEach((d) => d.classList.remove('open'));
    if (willOpen) dropdown?.classList.add('open');
  });
});

// Belt-and-suspenders for touch devices: a tap anywhere outside an open
// dropdown closes it, so it's never stuck open waiting for a second tap
// on the same toggle (see the ":hover" note in style.css for the other
// half of this fix).
document.addEventListener('click', (event) => {
  if (event.target.closest('.nav-dropdown-toggle')) return;
  if (event.target.closest('.nav-dropdown-menu')) return;
  document.querySelectorAll('.nav-dropdown.open').forEach((d) => d.classList.remove('open'));
});

(async () => {
  // #nav-login-link only exists on public pages (the header nav) — staff
  // admin pages have their own layout instead, but should still get the
  // alerts/mute toggle below, so this no longer bails out without it.
  const loginLink = document.getElementById('nav-login-link');

  function makeLogoutLink(logoutUrl) {
    if (!loginLink) return;
    loginLink.textContent = 'Log Out';
    loginLink.classList.remove('active');
    loginLink.href = '#';
    loginLink.addEventListener('click', async (event) => {
      event.preventDefault();
      await fetch(logoutUrl, { method: 'POST' });
      window.location.href = '/';
    });
  }

  try {
    const customerResponse = await fetch('/api/customer/me');
    if (customerResponse.ok) {
      makeLogoutLink('/api/customer/logout');
      return;
    }
    const staffResponse = await fetch('/api/auth/me');
    if (staffResponse.ok) {
      makeLogoutLink('/api/auth/logout');
      insertStaffNavDropdown();
      enableSpeechPrimingForStaff();
      startStaffAlertMuteToggle();
      startStaffTableOrderAlerts();
      startStaffFeedbackAlerts();
    }
  } catch {
    // leave the "Log In" link as-is
  }
})();

// A "Staff ▾" dropdown in the public site header, shown only to a logged-in
// staff member — same links as the .staff-tools-nav on every admin page,
// just also reachable from the customer-facing site without knowing a URL.
// Only public pages need this injected; admin pages already have their own
// staff-tools-nav in the page itself.
function insertStaffNavDropdown() {
  const siteNav = document.getElementById('site-nav');
  if (!siteNav || document.querySelector('.staff-tools-nav') || document.querySelector('.staff-nav-dropdown')) return;

  const dropdown = document.createElement('div');
  dropdown.className = 'nav-dropdown staff-nav-dropdown';
  dropdown.innerHTML = `
    <button class="nav-dropdown-toggle" type="button">Staff &#9662;</button>
    <div class="nav-dropdown-menu">
      <a href="/edit.html">Menu Editor</a>
      <a href="/table-orders-admin.html">Table Orders</a>
      <a href="/loyalty-admin.html">Loyalty</a>
      <a href="/waitlist-admin.html">Waitlist</a>
      <a href="/events-admin.html">Events</a>
      <a href="/table-card.html">Table Cards</a>
      <a href="/analytics.html">Analytics</a>
      <a href="/staff-rewards-admin.html">Staff Rewards</a>
      <a href="/competitor-pricing-admin.html">Competitor Pricing</a>
      <a href="/swag-admin.html">Swag</a>
      <a href="/gift-cards-admin.html">Gift Cards</a>
      <a href="/manage-users.html">Manage Users</a>
      <a href="/account.html">My Account</a>
    </div>
  `;
  dropdown.querySelector('.nav-dropdown-toggle').addEventListener('click', () => {
    const willOpen = !dropdown.classList.contains('open');
    document.querySelectorAll('.nav-dropdown.open').forEach((d) => d.classList.remove('open'));
    if (willOpen) dropdown.classList.add('open');
  });

  const loginLink = document.getElementById('nav-login-link');
  if (loginLink) {
    siteNav.insertBefore(dropdown, loginLink);
  } else {
    siteNav.appendChild(dropdown);
  }
}

// Whether a staff member has muted the spoken order alerts on this device.
// Per-browser (localStorage), not per-account — deliberately simple, since
// nothing here asked for the mute preference to follow a staff member
// between devices.
const ALERTS_MUTED_KEY = 'ohana_staff_alerts_muted';
function alertsMuted() {
  return localStorage.getItem(ALERTS_MUTED_KEY) === '1';
}
function setAlertsMuted(muted) {
  localStorage.setItem(ALERTS_MUTED_KEY, muted ? '1' : '0');
}

// iOS (every browser there, including Chrome — they're all WebKit under the
// hood, since Apple requires it) only lets speechSynthesis.speak() actually
// produce audio if speak() has been called at least once directly inside a
// real tap/click handler. A call made later from our poll()'s setInterval
// — exactly how the order alerts fire — is silently swallowed on iOS until
// that's happened once. This "primes" it on the very first tap anywhere on
// the page, so normal use of the site (tapping a nav link, logging in,
// anything) unlocks it without staff needing to know to do anything special.
//
// Only wired up for a confirmed logged-in staff member (see the IIFE
// above) — a random customer tapping the nav menu should never suddenly
// hear "Voice alerts on" spoken at them.
let speechPrimed = false;
function primeSpeechSynthesisOnce() {
  if (speechPrimed || !window.speechSynthesis) return;
  speechPrimed = true;
  speakNow('Voice alerts on');
}
function enableSpeechPrimingForStaff() {
  document.addEventListener('touchend', primeSpeechSynthesisOnce, { once: true, capture: true });
  document.addEventListener('click', primeSpeechSynthesisOnce, { once: true, capture: true });
}

// Deliberately does NOT cancel() any in-progress utterance first — several
// orders can legitimately arrive in the same poll, and cancelling every time
// would only ever let the last one be heard. See visibilitychange below for
// where the actual iOS "stuck queue" recovery happens instead.
function speakNow(text) {
  if (!window.speechSynthesis) return;
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = 0.95;
  window.speechSynthesis.speak(utterance);
}

// Keeps the screen from auto-locking while alerts are on — iOS suspends a
// backgrounded/locked tab's timers entirely, which would silently stop the
// order-alert polling (visual and spoken both) until someone taps the
// screen again. Best-effort: only recent browsers support this, and it has
// to be re-requested every time the tab becomes visible again (the OS
// releases it automatically when hidden).
let wakeLock = null;
async function requestWakeLockIfPossible() {
  if (!('wakeLock' in navigator) || alertsMuted()) return;
  try {
    wakeLock = await navigator.wakeLock.request('screen');
  } catch {
    // e.g. Low Power Mode, or unsupported — alerts still work as long as
    // the staff member's screen happens to stay on and the tab stays open.
  }
}

// A small always-visible toggle (not just shown when there's an active
// alert) so a staff member can mute/unmute regardless of what's happening
// right now, from any page.
function startStaffAlertMuteToggle() {
  // Registered here (rather than unconditionally at the top of the file)
  // since this whole function only ever runs for a confirmed logged-in
  // staff member — a customer's tab shouldn't be grabbing a screen wake
  // lock or fiddling with speechSynthesis just because they switched apps
  // and came back.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    requestWakeLockIfPossible();
    // iOS Safari/WebKit has a well-known bug where speechSynthesis can get
    // stuck reporting "still speaking" after the tab was backgrounded, and
    // silently swallows every speak() call from then on. Cancelling right
    // as the tab becomes visible again clears that stuck state without
    // risking cutting off a legitimate in-progress announcement (which
    // only happens while the tab is actually visible and running).
    window.speechSynthesis?.cancel();
  });

  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'staff-alert-mute-toggle';

  function paint() {
    const muted = alertsMuted();
    btn.textContent = muted ? '\u{1F515} Alerts muted' : '\u{1F514} Alerts on';
    btn.setAttribute('aria-pressed', String(muted));
    btn.title = muted ? 'Click to turn spoken order alerts back on' : 'Click to mute spoken order alerts';
  }

  paint();
  btn.addEventListener('click', () => {
    const nowMuted = !alertsMuted();
    setAlertsMuted(nowMuted);
    paint();
    if (nowMuted) {
      window.speechSynthesis?.cancel();
    } else {
      // Tapping this button is itself a real user gesture — use it to
      // (re-)prime iOS and grab the wake lock right away, instead of
      // waiting for the next unrelated tap.
      speechPrimed = true;
      speakNow('Voice alerts on');
      requestWakeLockIfPossible();
    }
  });
  getStaffAlertsContainer().appendChild(btn);
  requestWakeLockIfPossible();
}

function getStaffAlertsContainer() {
  let container = document.getElementById('staff-alerts-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'staff-alerts-container';
    container.className = 'staff-alerts-container';
    document.body.appendChild(container);
  }
  return container;
}

// Table id -> floor section ("dining"/"bar"/"sushi"/"deck"), fetched once and
// reused by the spoken order announcements below.
let tableMapSections = null;
async function getTableSection(tableId) {
  if (!tableMapSections) {
    tableMapSections = {};
    try {
      const response = await fetch('/api/table-map');
      const entries = response.ok ? await response.json() : [];
      entries.forEach((entry) => {
        tableMapSections[entry.id] = entry.section;
      });
    } catch {
      // leave the lookup empty — announcements still work, just without a section name
    }
  }
  return tableMapSections[tableId];
}

// Speaks a new table order aloud (table number + floor section) via the
// browser's built-in text-to-speech, so staff away from a screen still hear
// it. Best-effort: some browsers won't play audio at all until the page has
// had a user interaction, and that's fine — the visual badge below still works.
function announceNewOrder(tableId, section) {
  if (alertsMuted() || !window.speechSynthesis) return;
  const sectionLabel = section ? `, ${section}` : '';
  speakNow(`New order, table ${tableId}${sectionLabel}`);
}

// Speaks once a table has plausibly had enough time to cook — see
// tablesEligibleForAwaitingFlash for the exact threshold. "Order up" is the
// standard kitchen call for "this is ready," so it reads as unambiguous to
// staff rather than another generic chime.
function announceOrderUp(tableId, section) {
  if (alertsMuted() || !window.speechSynthesis) return;
  const sectionLabel = section ? `, ${section}` : '';
  speakNow(`Order up, table ${tableId}${sectionLabel}`);
}

// A table shouldn't be announced/flashed as ready for delivery the instant
// an order is entered — that's before the kitchen could plausibly have it
// ready. It becomes eligible once we're at whichever is greater: the average
// prep time of the single slowest dish still cooking there, or half the
// combined average prep time of everything cooking there. Mirrors the same
// function in table-orders-admin.js — duplicated rather than shared since
// these are separate plain <script> files with no module loader between them.
function tablesEligibleForAwaitingFlash(awaitingDelivery) {
  const byTable = {};
  awaitingDelivery.forEach((o) => {
    (byTable[o.tableId] = byTable[o.tableId] || []).push(o);
  });

  const eligible = new Set();
  Object.entries(byTable).forEach(([tableId, orders]) => {
    const durationsMs = [];
    const enteredTimesMs = [];
    orders.forEach((o) => {
      if (!o.enteredAt || !o.estimatedReadyAt) return;
      const entered = new Date(o.enteredAt).getTime();
      const ready = new Date(o.estimatedReadyAt).getTime();
      durationsMs.push(ready - entered);
      enteredTimesMs.push(entered);
    });
    if (!durationsMs.length) return;

    const longestDishMs = Math.max(...durationsMs);
    const halfOfTotalPrepMs = durationsMs.reduce((sum, d) => sum + d, 0) / 2;
    const delayMs = Math.max(longestDishMs, halfOfTotalPrepMs);
    const earliestEnteredMs = Math.min(...enteredTimesMs);
    if (Date.now() - earliestEnteredMs >= delayMs) {
      eligible.add(tableId);
    }
  });
  return eligible;
}

// A small floating indicator, shown site-wide to a logged-in staff member
// whenever a dine-in guest has tapped "Order" on a menu item — so a server
// walking the floor with the public site open on their phone still sees it,
// not just someone parked on the dedicated /table-orders-admin.html page.
function startStaffTableOrderAlerts() {
  const alertEl = document.createElement('a');
  alertEl.href = '/table-orders-admin.html';
  alertEl.className = 'staff-order-alert';
  alertEl.hidden = true;
  getStaffAlertsContainer().appendChild(alertEl);

  // Re-announced roughly once a minute for as long as an order stays
  // unaddressed — not just once on arrival — so a spoken reminder can't get
  // missed. Keyed by order id / table id -> the timestamp it was last
  // spoken, so a poll only re-announces once ANNOUNCE_REPEAT_MS has passed.
  const ANNOUNCE_REPEAT_MS = 60000;
  let lastAnnouncedNewOrderAt = {};
  let lastAnnouncedOrderUpAt = {};

  async function poll() {
    try {
      const response = await fetch('/api/table-orders/dashboard');
      if (!response.ok) return;
      const data = await response.json();
      const now = Date.now();

      for (const order of data.needsEntry) {
        const last = lastAnnouncedNewOrderAt[order.id];
        if (!last || now - last >= ANNOUNCE_REPEAT_MS) {
          lastAnnouncedNewOrderAt[order.id] = now;
          getTableSection(order.tableId).then((section) => announceNewOrder(order.tableId, section));
        }
      }
      const stillPendingIds = new Set(data.needsEntry.map((order) => order.id));
      Object.keys(lastAnnouncedNewOrderAt).forEach((id) => {
        if (!stillPendingIds.has(id)) delete lastAnnouncedNewOrderAt[id];
      });

      const currentEligibleTableIds = tablesEligibleForAwaitingFlash(data.awaitingDelivery);
      for (const tableId of currentEligibleTableIds) {
        const last = lastAnnouncedOrderUpAt[tableId];
        if (!last || now - last >= ANNOUNCE_REPEAT_MS) {
          lastAnnouncedOrderUpAt[tableId] = now;
          getTableSection(tableId).then((section) => announceOrderUp(tableId, section));
        }
      }
      Object.keys(lastAnnouncedOrderUpAt).forEach((tableId) => {
        if (!currentEligibleTableIds.has(tableId)) delete lastAnnouncedOrderUpAt[tableId];
      });

      const attention = data.needsEntry.length + data.readyCount;
      if (attention) {
        const parts = [];
        if (data.needsEntry.length) parts.push(`${data.needsEntry.length} new`);
        if (data.readyCount) parts.push(`${data.readyCount} ready`);
        alertEl.textContent = `${attention} table order${attention === 1 ? '' : 's'} (${parts.join(', ')})`;
        alertEl.hidden = false;

        // Jump straight to the section of whichever table needs attention
        // first (oldest new order, or else the oldest one awaiting delivery)
        // instead of always landing on the Dining tab.
        const oldest = data.needsEntry[0] || data.awaitingDelivery[0];
        alertEl.href = oldest
          ? await getTableSection(oldest.tableId).then((section) => (section ? `/table-orders-admin.html?section=${section}` : '/table-orders-admin.html'))
          : '/table-orders-admin.html';
      } else {
        alertEl.hidden = true;
      }
    } catch {
      // leave the indicator as-is until the next successful poll
    }
  }

  poll();
  setInterval(poll, 20000);
}

// Same pattern as the table-order alert, for new customer feedback — links
// to the analytics page, where the feedback report lives.
function startStaffFeedbackAlerts() {
  const alertEl = document.createElement('a');
  alertEl.href = '/analytics.html?section=feedback';
  alertEl.className = 'staff-order-alert';
  alertEl.hidden = true;
  getStaffAlertsContainer().appendChild(alertEl);

  async function poll() {
    try {
      const response = await fetch('/api/feedback/unacknowledged-count');
      if (!response.ok) return;
      const data = await response.json();
      if (data.count) {
        alertEl.textContent = `${data.count} new feedback submission${data.count === 1 ? '' : 's'}`;
        alertEl.hidden = false;
      } else {
        alertEl.hidden = true;
      }
    } catch {
      // leave the indicator as-is until the next successful poll
    }
  }

  poll();
  setInterval(poll, 20000);
}

// A small floating "Feedback" tab, shown to every visitor on every public
// page — opens a lightweight form to leave feedback on the website, food, or
// service. No login required.
(() => {
  const tabBtn = document.createElement('button');
  tabBtn.type = 'button';
  tabBtn.className = 'feedback-tab-btn';
  tabBtn.textContent = 'Feedback';
  document.body.appendChild(tabBtn);

  let modal = null;
  let selectedRating = 0;

  function paintStars() {
    modal.querySelectorAll('.feedback-star').forEach((b) => {
      b.classList.toggle('active', Number(b.dataset.value) <= selectedRating);
    });
  }

  function ensureFeedbackModal() {
    if (modal) return modal;
    modal = document.createElement('div');
    modal.className = 'item-modal-overlay';
    modal.hidden = true;
    modal.innerHTML = `
      <div class="item-modal">
        <button type="button" class="item-modal-close" aria-label="Close">&times;</button>
        <h3 class="item-modal-name">Share Your Feedback</h3>
        <p class="hint">Tell us about the website, the food, or the service — whatever's on your mind.</p>
        <form id="feedback-form">
          <label>What's this about?
            <select id="feedback-category">
              <option value="food">Food</option>
              <option value="service">Service</option>
              <option value="website">Website</option>
              <option value="other">Other</option>
            </select>
          </label>
          <div class="feedback-stars">
            ${[1, 2, 3, 4, 5]
              .map((n) => `<button type="button" class="feedback-star" data-value="${n}" aria-label="${n} star${n > 1 ? 's' : ''}">&#9733;</button>`)
              .join('')}
          </div>
          <label>Your feedback
            <textarea id="feedback-message" rows="4" required></textarea>
          </label>
          <label>Email (optional, if you'd like a reply)
            <input type="email" id="feedback-email" />
          </label>
          <button type="submit">Send Feedback</button>
          <p id="feedback-status" class="status"></p>
        </form>
      </div>
    `;
    document.body.appendChild(modal);

    modal.addEventListener('click', (event) => {
      if (event.target === modal) modal.hidden = true;
    });
    modal.querySelector('.item-modal-close').addEventListener('click', () => {
      modal.hidden = true;
    });
    modal.querySelectorAll('.feedback-star').forEach((b) => {
      b.addEventListener('click', () => {
        const value = Number(b.dataset.value);
        selectedRating = selectedRating === value ? 0 : value;
        paintStars();
      });
    });

    modal.querySelector('#feedback-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const statusEl = modal.querySelector('#feedback-status');
      const messageInput = modal.querySelector('#feedback-message');
      const emailInput = modal.querySelector('#feedback-email');
      const message = messageInput.value.trim();
      if (!message) return;

      statusEl.textContent = 'Sending...';
      statusEl.classList.remove('status-error', 'status-ok');
      try {
        const response = await fetch('/api/feedback', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            category: modal.querySelector('#feedback-category').value,
            rating: selectedRating || null,
            message,
            page: window.location.pathname,
            contactEmail: emailInput.value.trim() || null,
          }),
        });
        if (!response.ok) throw new Error(`Failed (${response.status}).`);
        statusEl.textContent = 'Thank you for your feedback!';
        statusEl.classList.add('status-ok');
        messageInput.value = '';
        emailInput.value = '';
        selectedRating = 0;
        paintStars();
        setTimeout(() => {
          modal.hidden = true;
          statusEl.textContent = '';
        }, 1800);
      } catch (error) {
        statusEl.textContent = error.message;
        statusEl.classList.add('status-error');
      }
    });

    return modal;
  }

  tabBtn.addEventListener('click', () => {
    ensureFeedbackModal().hidden = false;
  });
})();

// Anonymous, aggregate-only "time on page" tracking — no cookies, no
// per-visitor identity, just how long this one page view lasted before the
// tab was hidden or closed. See AnalyticsStore.recordDwell server-side.
(() => {
  const startTime = performance.now();
  let sent = false;

  function sendDwell() {
    if (sent) return;
    sent = true;
    const seconds = (performance.now() - startTime) / 1000;
    const payload = JSON.stringify({ path: window.location.pathname, seconds });
    if (navigator.sendBeacon) {
      navigator.sendBeacon('/api/analytics/dwell', new Blob([payload], { type: 'application/json' }));
    } else {
      fetch('/api/analytics/dwell', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: payload,
        keepalive: true,
      }).catch(() => {});
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') sendDwell();
  });
  window.addEventListener('pagehide', sendDwell);
})();
