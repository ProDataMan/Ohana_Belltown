document.getElementById('nav-toggle')?.addEventListener('click', () => {
  document.getElementById('site-nav')?.classList.toggle('open');
});

document.querySelectorAll('.nav-dropdown-toggle').forEach((btn) => {
  btn.addEventListener('click', () => {
    btn.parentElement?.classList.toggle('open');
  });
});

(async () => {
  const loginLink = document.getElementById('nav-login-link');
  if (!loginLink) return;

  function makeLogoutLink(logoutUrl) {
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
      startStaffTableOrderAlerts();
      startStaffFeedbackAlerts();
    }
  } catch {
    // leave the "Log In" link as-is
  }
})();

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

  async function poll() {
    try {
      const response = await fetch('/api/table-orders/dashboard');
      if (!response.ok) return;
      const data = await response.json();
      const attention = data.needsEntry.length + data.readyCount;
      if (attention) {
        const parts = [];
        if (data.needsEntry.length) parts.push(`${data.needsEntry.length} new`);
        if (data.readyCount) parts.push(`${data.readyCount} ready`);
        alertEl.textContent = `${attention} table order${attention === 1 ? '' : 's'} (${parts.join(', ')})`;
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

// Same pattern as the table-order alert, for new customer feedback — links
// to the analytics page, where the feedback report lives.
function startStaffFeedbackAlerts() {
  const alertEl = document.createElement('a');
  alertEl.href = '/analytics.html#feedback';
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
