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
    }
  } catch {
    // leave the "Log In" link as-is
  }
})();

// A small floating indicator, shown site-wide to a logged-in staff member
// whenever a dine-in guest has tapped "Order" on a menu item — so a server
// walking the floor with the public site open on their phone still sees it,
// not just someone parked on the dedicated /table-orders-admin.html page.
function startStaffTableOrderAlerts() {
  const alertEl = document.createElement('a');
  alertEl.href = '/table-orders-admin.html';
  alertEl.className = 'staff-order-alert';
  alertEl.hidden = true;
  document.body.appendChild(alertEl);

  async function poll() {
    try {
      const response = await fetch('/api/table-orders/pending');
      if (!response.ok) return;
      const orders = await response.json();
      if (orders.length) {
        alertEl.textContent = `${orders.length} pending table order${orders.length === 1 ? '' : 's'}`;
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
