// favicon.ico at the site root already covers most browsers with zero markup
// (the default path they request automatically) — these explicit tags add a
// crisper PNG for browsers that prefer one, plus the iOS home-screen icon.
// Injected here (loaded on every page) instead of duplicating <link> tags
// across 20+ HTML files.
[
  { rel: 'icon', type: 'image/png', href: '/images/favicon-32.png' },
  { rel: 'apple-touch-icon', href: '/images/apple-touch-icon.png' },
].forEach(({ rel, type, href }) => {
  const link = document.createElement('link');
  link.rel = rel;
  if (type) link.type = type;
  link.href = href;
  document.head.appendChild(link);
});

// On phones the open menu hangs below the pinned header; without a height
// limit, a long submenu (Staff) ran off the bottom of the screen with no way
// to scroll to it, and the Call / Order / Directions bar covered the last
// links. This fits the menu between the header and that bar, and the menu
// scrolls inside itself (see .site-nav in style.css).
function fitMobileNav() {
  const nav = document.getElementById('site-nav');
  const header = document.querySelector('.site-header');
  if (!nav || !header) return;
  const bar = document.querySelector('.mobile-cta-bar');
  const barHeight = bar && getComputedStyle(bar).display !== 'none' ? bar.offsetHeight : 0;
  const available = window.innerHeight - header.getBoundingClientRect().bottom - barHeight;
  nav.style.setProperty('--nav-max-height', `${Math.max(available, 160)}px`);
}

/// After a submenu opens, scroll the menu so the submenu is in view.
function revealDropdown(dropdown) {
  const nav = document.getElementById('site-nav');
  if (!nav || !nav.classList.contains('open') || !dropdown) return;
  requestAnimationFrame(() => {
    const menu = dropdown.querySelector('.nav-dropdown-menu') || dropdown;
    const overflow = menu.getBoundingClientRect().bottom - nav.getBoundingClientRect().bottom;
    if (overflow > 0) nav.scrollBy({ top: overflow + 12, behavior: 'smooth' });
  });
}

document.getElementById('nav-toggle')?.addEventListener('click', () => {
  fitMobileNav();
  const open = document.getElementById('site-nav')?.classList.toggle('open');
  // The floating Feedback / staff alert buttons would sit over the menu.
  document.body.classList.toggle('nav-open', Boolean(open));
});
window.addEventListener('resize', fitMobileNav);

document.querySelectorAll('.nav-dropdown-toggle').forEach((btn) => {
  btn.addEventListener('click', () => {
    const dropdown = btn.parentElement;
    const willOpen = !dropdown?.classList.contains('open');
    document.querySelectorAll('.nav-dropdown.open').forEach((d) => d.classList.remove('open'));
    if (willOpen) {
      dropdown?.classList.add('open');
      revealDropdown(dropdown);
    }
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

// One shared "who's signed in" check per page load. /api/session answers 200
// whether or not anyone is signed in, so a signed-out guest no longer gets a
// 401 (and a console error) from every script that asks. Other scripts read
// window.ohanaSession instead of calling /api/auth/me or /api/customer/me.
window.ohanaSession = window.ohanaSession || fetch('/api/session')
  .then((response) => (response.ok ? response.json() : {}))
  .catch(() => ({}));

// Page views are counted here, by the page's own script, rather than by the
// server for every request — most bots never run scripts, so they no longer
// inflate the totals. Skipped on devices marked "don't count".
(() => {
  if (document.cookie.split('; ').includes('ohana_no_track=1')) return;
  const payload = JSON.stringify({ path: window.location.pathname });
  if (navigator.sendBeacon && navigator.sendBeacon('/api/analytics/pageview', new Blob([payload], { type: 'application/json' }))) return;
  fetch('/api/analytics/pageview', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: payload, keepalive: true }).catch(() => {});
})();

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
    const session = await window.ohanaSession;
    if (session.customer) {
      makeLogoutLink('/api/customer/logout');
      return;
    }
    if (session.staff) {
      // A phone or computer staff sign in on is theirs or the restaurant's:
      // keep it out of the reports from now on, even when signed out (see
      // /dont-count-this-device.html to undo).
      document.cookie = 'ohana_no_track=1; path=/; max-age=157680000; SameSite=Lax';
      makeLogoutLink('/api/auth/logout');
      insertStaffNavDropdown();
      enableSpeechPrimingForStaff();
      startStaffAlertMuteToggle();
      startStaffTableOrderAlerts();
      startStaffFeedbackAlerts();
      if (session.staff.role === 'admin') {
        startStaffCompetitorPhotoAlerts();
      }
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
      <a href="/qr-visits.html">QR Visits</a>
      <a href="/qr-insights.html">QR Insights</a>
      <a href="/pos-orders.html">POS Orders</a>
      <a href="/hours-admin.html">Hours</a>
      <a href="/daily-specials-admin.html">Daily Specials</a>
      <a href="/staff-rewards-admin.html">Staff Rewards</a>
      <a href="/competitor-pricing-admin.html">Competitor Pricing</a>
      <a href="/swag-admin.html">Swag</a>
      <a href="/gift-cards-admin.html">Gift Cards</a>
      <a href="/manage-users.html">Manage Users</a>
      <a href="/account.html">My Account</a>
      <a href="/help.html">Help</a>
    </div>
  `;
  dropdown.querySelector('.nav-dropdown-toggle').addEventListener('click', () => {
    const willOpen = !dropdown.classList.contains('open');
    document.querySelectorAll('.nav-dropdown.open').forEach((d) => d.classList.remove('open'));
    if (willOpen) {
      dropdown.classList.add('open');
      revealDropdown(dropdown);
    }
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

// Speaks a table's order counts aloud (table number + floor section) via the
// browser's built-in text-to-speech, so staff away from a screen still hear
// it. Best-effort: some browsers won't play audio at all until the page has
// had a user interaction, and that's fine — the visual badge below still works.
// newCount is items not yet confirmed/entered by a server; waitingCount is
// items already entered but not yet delivered to the table.
function announceNewOrder(tableId, section, newCount, waitingCount) {
  if (alertsMuted() || !window.speechSynthesis) return;
  const sectionLabel = section ? `, ${section}` : '';
  const itemWord = newCount === 1 ? 'item' : 'items';
  const waitingClause = waitingCount > 0 ? `, waiting for ${waitingCount} to be delivered` : '';
  speakNow(`${newCount} new ${itemWord} added to order at table ${tableId}${sectionLabel}${waitingClause}`);
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

      // Batched per table rather than per item: a table with 3 pending items
      // gets one "3 new items..." announcement, not three separate ones.
      const pendingByTable = {};
      data.needsEntry.forEach((order) => {
        pendingByTable[order.tableId] = (pendingByTable[order.tableId] || 0) + 1;
      });
      const awaitingByTable = {};
      data.awaitingDelivery.forEach((order) => {
        awaitingByTable[order.tableId] = (awaitingByTable[order.tableId] || 0) + 1;
      });

      for (const [tableId, newCount] of Object.entries(pendingByTable)) {
        const last = lastAnnouncedNewOrderAt[tableId];
        if (!last || now - last >= ANNOUNCE_REPEAT_MS) {
          lastAnnouncedNewOrderAt[tableId] = now;
          const waitingCount = awaitingByTable[tableId] || 0;
          getTableSection(tableId).then((section) => announceNewOrder(tableId, section, newCount, waitingCount));
        }
      }
      const stillPendingTableIds = new Set(Object.keys(pendingByTable));
      Object.keys(lastAnnouncedNewOrderAt).forEach((tableId) => {
        if (!stillPendingTableIds.has(tableId)) delete lastAnnouncedNewOrderAt[tableId];
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

// Same pattern again, for competitor menu photos still waiting to be read
// for prices/dishes — admin-only (gated by the caller, see the staff-detection
// block above) since competitor pricing is strategy data, not general staff
// info. Links to the Competitor Pricing admin page, where the photos live.
function startStaffCompetitorPhotoAlerts() {
  const alertEl = document.createElement('a');
  alertEl.href = '/competitor-pricing-admin.html';
  alertEl.className = 'staff-order-alert';
  alertEl.hidden = true;
  getStaffAlertsContainer().appendChild(alertEl);

  async function poll() {
    try {
      const response = await fetch('/api/competitor-pricing/unreviewed-photo-count');
      if (!response.ok) return;
      const data = await response.json();
      if (data.count) {
        alertEl.textContent = `${data.count} unreviewed menu photo${data.count === 1 ? '' : 's'}`;
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

// "Scan session length" — total time spent on the site after a QR scan
// lands, across however many pages get browsed in that tab session (not
// just the one landing page, unlike the dwell tracker above). The arrival
// timestamp is stashed in sessionStorage the same way getTableId() stashes
// ohana_table_id in menu-section.js, so it survives internal navigation —
// and is only sent once per session (guarded in sessionStorage too, since
// each page load runs this IIFE fresh) to avoid double-counting the same
// stretch of time from more than one page's hidden/pagehide event.
(() => {
  const params = new URLSearchParams(window.location.search);
  const freshScan = Boolean(params.get('table')) || params.get('hh') === '1' || params.get('prices') === '1';
  if (freshScan && !sessionStorage.getItem('ohana_scan_arrived_at')) {
    sessionStorage.setItem('ohana_scan_arrived_at', String(Date.now()));
  }
  const arrivedAt = sessionStorage.getItem('ohana_scan_arrived_at');
  if (!arrivedAt) return;

  let sent = false;
  function sendScanSession() {
    if (sent || sessionStorage.getItem('ohana_scan_session_sent') === '1') return;
    sent = true;
    sessionStorage.setItem('ohana_scan_session_sent', '1');
    const seconds = (Date.now() - Number(arrivedAt)) / 1000;
    const payload = JSON.stringify({ seconds });
    if (navigator.sendBeacon) {
      navigator.sendBeacon('/api/analytics/scan-session', new Blob([payload], { type: 'application/json' }));
    } else {
      fetch('/api/analytics/scan-session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: payload,
        keepalive: true,
      }).catch(() => {});
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') sendScanSession();
  });
  window.addEventListener('pagehide', sendScanSession);
})();

// Scroll depth — which thresholds of a page's scrollable height someone
// actually reaches, bucketed (25/50/75/100%) rather than tracked
// continuously. Fires once per distinct threshold reached, flushed as a
// batch at tab-hide/close the same way menu-item impressions are.
(() => {
  const thresholds = [25, 50, 75, 100];
  const reached = new Set();
  const section = window.MENU_SECTION || window.location.pathname;

  function checkScroll() {
    const doc = document.documentElement;
    const scrollable = doc.scrollHeight - doc.clientHeight;
    const pct = scrollable <= 0 ? 100 : Math.min(100, Math.round((window.scrollY / scrollable) * 100));
    thresholds.forEach((t) => {
      if (pct >= t) reached.add(t);
    });
  }

  function flush() {
    if (!reached.size) return;
    const buckets = Array.from(reached);
    reached.clear();
    const payload = JSON.stringify({ section, buckets });
    if (navigator.sendBeacon) {
      navigator.sendBeacon('/api/analytics/scroll-depth', new Blob([payload], { type: 'application/json' }));
    } else {
      fetch('/api/analytics/scroll-depth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: payload,
        keepalive: true,
      }).catch(() => {});
    }
  }

  window.addEventListener('scroll', checkScroll, { passive: true });
  checkScroll();
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') flush();
  });
  window.addEventListener('pagehide', flush);
})();

// Where visits come from, and the actions that matter: on the first page of
// a tab session, report the traffic source (QR code, Google, Google Maps,
// Instagram, a utm_ campaign link, or direct) and landing page once; on
// every page, report taps on "Order Online" (ChowNow), phone numbers,
// directions, email, and social links, tagged with that same source. Counts
// only — the per-browser id is sent just so the server can count unique
// visitors per day, and is never stored. Must run before the QR visit
// tracker below, which strips `qr=1` from the address bar.
(() => {
  const SOURCE_KEY = 'ohana_visit_source';

  function classifyReferrer(referrer) {
    let url;
    try {
      url = new URL(referrer);
    } catch {
      return 'direct';
    }
    const host = url.hostname.replace(/^www\./, '').toLowerCase();
    if (host === window.location.hostname.replace(/^www\./, '').toLowerCase()) return null;
    if (host === 'maps.app.goo.gl' || host.startsWith('maps.google.') || (host.startsWith('google.') && url.pathname.startsWith('/maps'))) return 'google-maps';
    if (host.startsWith('google.') || host.endsWith('.google.com')) return 'google';
    if (/(^|\.)(bing\.com|duckduckgo\.com|yahoo\.com|ecosia\.org|search\.brave\.com)$/.test(host)) return 'search-other';
    if (/(^|\.)instagram\.com$/.test(host)) return 'instagram';
    if (/(^|\.)(facebook\.com|fb\.com|fb\.me|messenger\.com)$/.test(host)) return 'facebook';
    if (/(^|\.)yelp\.[a-z.]+$/.test(host)) return 'yelp';
    if (/(^|\.)tiktok\.com$/.test(host)) return 'tiktok';
    if (/(^|\.)(t\.co|x\.com|twitter\.com)$/.test(host)) return 'x';
    if (/(^|\.)tripadvisor\.[a-z.]+$/.test(host)) return 'tripadvisor';
    if (/(^|\.)reddit\.com$/.test(host)) return 'reddit';
    if (/(^|\.)chownow\.com$/.test(host)) return 'chownow';
    return `other:${host.slice(0, 50)}`;
  }

  function currentSource() {
    try {
      return sessionStorage.getItem(SOURCE_KEY) || 'unknown';
    } catch {
      return 'unknown';
    }
  }

  function beacon(url, body) {
    const payload = JSON.stringify(body);
    if (navigator.sendBeacon && navigator.sendBeacon(url, new Blob([payload], { type: 'application/json' }))) return;
    fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: payload, keepalive: true }).catch(() => {});
  }

  let isNewSession = false;
  try {
    isNewSession = !sessionStorage.getItem(SOURCE_KEY);
  } catch {}
  if (isNewSession) {
    const params = new URLSearchParams(window.location.search);
    let source = null;
    if (params.get('qr') === '1' || params.get('table')) source = 'qr';
    else if (params.get('utm_source')) source = params.get('utm_source').toLowerCase().replace(/[^a-z0-9._:-]/g, '-').slice(0, 60);
    else source = document.referrer ? classifyReferrer(document.referrer) : 'direct';
    if (source) {
      try {
        sessionStorage.setItem(SOURCE_KEY, source);
      } catch {}
      let deviceId = null;
      try {
        deviceId = localStorage.getItem('ohana_device_id');
        if (!deviceId) {
          deviceId = window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`;
          localStorage.setItem('ohana_device_id', deviceId);
        }
      } catch {}
      const campaign = params.get('utm_campaign');
      beacon('/api/analytics/visit', {
        source,
        landing: window.location.pathname,
        campaign: campaign ? campaign.toLowerCase().replace(/[^a-z0-9._:-]/g, '-').slice(0, 60) : null,
        deviceId,
      });
    }
  }

  const SOCIAL = [
    [/instagram\.com/, 'instagram'],
    [/(facebook\.com|fb\.com|fb\.me)/, 'facebook'],
    [/tiktok\.com/, 'tiktok'],
    [/yelp\.[a-z.]+/, 'yelp'],
    [/(x\.com|twitter\.com)/, 'x'],
    [/tripadvisor\./, 'tripadvisor'],
    [/(g\.page|search\.google\.com\/local\/writereview|google\.com\/maps\/place.*review)/, 'google-reviews'],
  ];

  function actionFor(link) {
    const href = (link.getAttribute('href') || '').trim();
    if (!href) return null;
    if (href.startsWith('tel:')) return 'call';
    if (href.startsWith('mailto:')) return 'email';
    if (/chownow\.com/i.test(href)) return 'order-online';
    if (/(maps\.app\.goo\.gl|maps\.google\.|google\.[a-z.]+\/maps\/(dir|search)|maps\.apple\.com|goo\.gl\/maps)/i.test(href)) return 'directions';
    for (const [pattern, site] of SOCIAL) {
      if (pattern.test(href)) return `social:${site}`;
    }
    return null;
  }

  // Capture phase, so the tap is recorded even if another handler stops
  // propagation; sendBeacon survives the page navigating away.
  document.addEventListener(
    'click',
    (event) => {
      const link = event.target.closest && event.target.closest('a[href]');
      if (!link) return;
      const action = actionFor(link);
      if (action) beacon('/api/analytics/action', { action, page: window.location.pathname, source: currentSource() });
    },
    true
  );
})();

// QR visit tracker — what someone who scanned a QR code looked at, page by
// page and item by item, attributed to the table on the card. A visit starts
// on a fresh scan (/scan adds `qr=1` to the landing URL, and a `table` there
// also counts for older printed links) and lasts for this tab until an
// hour passes with no activity, so a phone left on the menu tab overnight
// doesn't attribute tomorrow's browsing to tonight's table. Uses the same
// per-browser ohana_device_id menu-section.js uses for order history.
// Disclosed on /privacy; see QRVisitStore server-side.
(() => {
  const VISIT_KEY = 'ohana_qr_visit';
  const IDLE_LIMIT_MS = 60 * 60 * 1000;

  function randomId() {
    return window.crypto && window.crypto.randomUUID
      ? window.crypto.randomUUID()
      : `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}-${Math.random().toString(16).slice(2)}`;
  }

  function deviceId() {
    try {
      let id = localStorage.getItem('ohana_device_id');
      if (!id) {
        id = randomId();
        localStorage.setItem('ohana_device_id', id);
      }
      return id;
    } catch {
      return null;
    }
  }

  function readVisit() {
    try {
      const visit = JSON.parse(sessionStorage.getItem(VISIT_KEY) || 'null');
      if (visit && Date.now() - visit.lastAt < IDLE_LIMIT_MS) return visit;
    } catch {}
    return null;
  }

  function saveVisit(visit) {
    try {
      sessionStorage.setItem(VISIT_KEY, JSON.stringify(visit));
    } catch {}
  }

  const params = new URLSearchParams(window.location.search);
  const freshScan = params.get('qr') === '1' || Boolean(params.get('table'));
  let visit = readVisit();
  if (freshScan) {
    const table = params.get('table') || null;
    // `card=hh` is the "flip the table card over" Happy Hour QR (see /scan).
    let source = 'front-door';
    if (params.get('card') === 'hh') source = 'happy-hour-card';
    else if (table) source = 'table';
    else if (window.location.pathname.startsWith('/happy-hour')) source = 'happy-hour';
    // A re-scan of the same table within an active visit (or an old printed
    // ?table= link reloaded) continues it rather than starting another.
    if (!visit || params.get('qr') === '1' || visit.table !== table) {
      visit = { id: randomId(), table, source, firstAt: Date.now(), lastAt: Date.now(), started: false };
    }
  }
  if (params.get('qr') === '1') {
    params.delete('qr');
    params.delete('card');
    const query = params.toString();
    try {
      history.replaceState(null, '', window.location.pathname + (query ? `?${query}` : '') + window.location.hash);
    } catch {}
  }
  const device = deviceId();
  if (!visit || !device) {
    window.ohanaTrackVisit = () => {};
    return;
  }

  function send(type, fields) {
    visit.lastAt = Date.now();
    saveVisit(visit);
    const payload = JSON.stringify({ visitId: visit.id, deviceId: device, table: visit.table, type, ...fields });
    if (navigator.sendBeacon && navigator.sendBeacon('/api/analytics/qr-visit-event', new Blob([payload], { type: 'application/json' }))) {
      return;
    }
    fetch('/api/analytics/qr-visit-event', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload,
      keepalive: true,
    }).catch(() => {});
  }

  if (!visit.started) {
    visit.started = true;
    send('start', { source: visit.source, page: window.location.pathname });
  }
  send('page', { page: window.location.pathname });
  if (!visit.firstAt) {
    visit.firstAt = Date.now();
    saveVisit(visit);
  }
  scheduleReviewPrompt();

  // A Google review nudge, at the moment a guest is most likely happy to
  // leave one: 25 minutes into a QR visit (their food has come). Once per
  // visit, and not again on this phone for 30 days after it's shown, or
  // ever once they've tapped through to leave one.
  function scheduleReviewPrompt() {
    const REVIEW_AFTER_MS = 25 * 60 * 1000;
    const REVIEW_URL = 'https://search.google.com/local/writereview?placeid=ChIJXUznpU0VkFQRcc35QzkAM7w';
    try {
      if (localStorage.getItem('ohana_reviewed')) return;
      const lastAsked = Number(localStorage.getItem('ohana_review_asked_at') || 0);
      if (Date.now() - lastAsked < 30 * 24 * 60 * 60 * 1000) return;
    } catch {
      return;
    }
    if (visit.reviewAsked) return;
    const wait = Math.max(0, visit.firstAt + REVIEW_AFTER_MS - Date.now());
    setTimeout(() => {
      if (document.visibilityState === 'hidden' || document.querySelector('.scan-feature-overlay, .yoshi-overlay, #item-modal-overlay:not([hidden])')) {
        // Try again shortly rather than cover a popup or a dish.
        setTimeout(scheduleReviewPrompt, 60 * 1000);
        return;
      }
      if (readVisit()?.reviewAsked) return;
      visit.reviewAsked = true;
      saveVisit(visit);
      try {
        localStorage.setItem('ohana_review_asked_at', String(Date.now()));
      } catch {}
      const toast = document.createElement('div');
      toast.className = 'review-prompt';
      toast.setAttribute('role', 'status');
      toast.innerHTML = `
        <p><strong>Enjoying your meal?</strong> A quick Google review helps our little ohana a lot. Mahalo!</p>
        <div class="review-prompt-actions">
          <a class="cta-button review-prompt-go" href="${REVIEW_URL}" target="_blank" rel="noopener">Leave a review</a>
          <button type="button" class="cta-button secondary review-prompt-close">Not now</button>
        </div>
      `;
      document.body.appendChild(toast);
      send('feature-shown', { page: window.location.pathname, itemName: 'Google review prompt' });
      toast.querySelector('.review-prompt-go').addEventListener('click', () => {
        try {
          localStorage.setItem('ohana_reviewed', '1');
        } catch {}
        send('feature-tap', { page: window.location.pathname, itemName: 'Google review prompt' });
        const payload = JSON.stringify({ action: 'review', page: window.location.pathname, source: 'qr-review-prompt' });
        if (navigator.sendBeacon) navigator.sendBeacon('/api/analytics/action', new Blob([payload], { type: 'application/json' }));
        toast.hidden = true;
      });
      toast.querySelector('.review-prompt-close').addEventListener('click', () => {
        toast.hidden = true;
      });
    }, wait);
  }

  // When the guest stops looking (closes the tab, switches apps, or moves to
  // another page), so the visit's length runs to then instead of stopping
  // at their last tap. Once per time the page is hidden.
  let leaveSent = false;
  const sendLeave = () => {
    if (leaveSent) return;
    leaveSent = true;
    send('leave', { page: window.location.pathname });
  };
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') sendLeave();
    else leaveSent = false;
  });
  window.addEventListener('pagehide', sendLeave);

  /// For menu-section.js: 'details', 'photo', 'search', 'add-to-order'.
  window.ohanaTrackVisit = (type, fields = {}) => send(type, { page: window.location.pathname, ...fields });
})();

// Opening hours, from the staff Hours page (GET /api/hours, which also works
// out "open now", the kitchen, and Happy Hour for this moment). Fills in the
// footer on every page, a status line on the phone's bottom bar, and any
// [data-hours] placeholder: "hero" / "today" on the home page, "week" on
// Contact and the FAQ, "happy-hour" wherever the Happy Hour times are shown.
// Also adds the hours to the home page's structured data for search engines.
// window.ohanaHours is shared, e.g. with the Happy Hour notes in menu-section.js.
window.ohanaHours = window.ohanaHours || fetch('/api/hours')
  .then((response) => (response.ok ? response.json() : null))
  .catch(() => null);

(async () => {
  const hours = await window.ohanaHours;
  if (!hours) return;
  const esc = (value) => String(value)
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  const now = hours.now;
  const statusClass = now.open ? 'hours-open' : 'hours-closed';
  const weekLines = hours.week.map((line) => `<li><span>${esc(line.label)}</span> <span>${esc(line.hours)}</span></li>`).join('');
  const upcoming = hours.upcoming.length
    ? `<p class="hours-upcoming"><strong>Coming up:</strong> ${hours.upcoming.map((u) => `${esc(u.label)}: ${esc(u.hours)}`).join(' · ')}</p>`
    : '';

  // Footer, every page.
  const footerColumn = document.querySelector('.site-footer-inner > div');
  if (footerColumn) {
    const block = document.createElement('div');
    block.className = 'footer-hours';
    block.innerHTML = `
      <p class="footer-brand">${esc(hours.seasonLabel || 'Hours')}</p>
      <p class="hours-status ${statusClass}">${esc(now.label)}</p>
      <ul class="hours-week">${weekLines}</ul>
      ${hours.kitchenSummary ? `<p class="hours-note">${esc(hours.kitchenSummary)}</p>` : ''}
      ${hours.happyHourSummary ? `<p class="hours-note">Happy Hour ${esc(hours.happyHourSummary)}</p>` : ''}
      ${upcoming}
    `;
    footerColumn.after(block);
  }

  // Phone bottom bar: one line over Call / Order / Directions.
  const bar = document.querySelector('.mobile-cta-bar');
  if (bar && !bar.querySelector('.mobile-cta-status')) {
    const line = document.createElement('div');
    line.className = `mobile-cta-status ${statusClass}`;
    line.textContent = [now.label, now.happyHourLabel].filter(Boolean).join(' · ');
    bar.prepend(line);
    document.body.classList.add('has-mobile-cta-status');
  }

  // Home page banner and "Today at Ohana" strip.
  document.querySelectorAll('[data-hours="hero"]').forEach((el) => {
    el.innerHTML = [now.label, now.happyHourLabel].filter(Boolean).map(esc).join(' · ');
    el.classList.add(statusClass);
    el.hidden = false;
  });
  document.querySelectorAll('[data-hours="today"]').forEach((el) => {
    const facts = [
      `<li><strong>${esc(now.today)}</strong></li>`,
      ...(hours.todayDeals || []).map((deal) => `<li class="today-deal"><a href="/specials">${esc(deal.title)}</a>: <strong>${esc(deal.deal)}</strong></li>`),
      now.kitchenLabel ? `<li>${esc(now.kitchenLabel)}</li>` : '',
      `<li>${now.happyHourNow ? `<strong>${esc(now.happyHourLabel)}</strong> · ` : ''}<a href="/happy-hour">Happy Hour</a> ${esc(hours.happyHourSummary || '')}</li>`,
      hours.todaySpecials.length
        ? `<li><a href="/specials">Today's special${hours.todaySpecials.length === 1 ? '' : 's'}</a>: ${hours.todaySpecials.slice(0, 3).map(esc).join(', ')}</li>`
        : '',
    ];
    el.innerHTML = `<div class="today-strip-inner"><p class="today-strip-title ${statusClass}">${esc(now.label)}</p><ul>${facts.join('')}</ul></div>`;
    el.hidden = false;
  });

  // The full week (Contact, FAQ).
  document.querySelectorAll('[data-hours="week"]').forEach((el) => {
    el.innerHTML = `
      <p class="hours-status ${statusClass}">${esc(now.label)}</p>
      ${hours.seasonLabel ? `<p class="hours-season">${esc(hours.seasonLabel)}</p>` : ''}
      <ul class="hours-week">${weekLines}</ul>
      ${hours.kitchenSummary ? `<p class="hours-note">${esc(hours.kitchenSummary)}</p>` : ''}
      ${hours.happyHourSummary ? `<p class="hours-note">Happy Hour ${esc(hours.happyHourSummary)}</p>` : ''}
      ${upcoming}
      ${hours.holidayNote ? `<p class="hours-note">${esc(hours.holidayNote)}</p>` : ''}
    `;
  });

  // Happy Hour times, worked out against the opening hours.
  if (hours.happyHourSummary) {
    document.querySelectorAll('[data-hours="happy-hour"]').forEach((el) => {
      el.textContent = hours.happyHourSummary;
    });
  }

  // Search engines: add the hours to the home page's Restaurant data.
  if (hours.openingHoursSpecification.length) {
    document.querySelectorAll('script[type="application/ld+json"]').forEach((script) => {
      try {
        const data = JSON.parse(script.textContent);
        if (data['@type'] !== 'Restaurant') return;
        data.openingHoursSpecification = hours.openingHoursSpecification;
        script.textContent = JSON.stringify(data);
      } catch {}
    });
  }
})();
