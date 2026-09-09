async function staffFetch(url, options = {}) {
  const response = await fetch(url, options);
  if (response.status === 401) {
    window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
  }
  return response;
}

// entertainmentProvider (outside DJs/promoters) is blocked server-side from
// everything but entertainment bookings + their own account — this just
// trims the shared staff-tools-nav to match, so it doesn't show a page full
// of links that would 403 if clicked. The backend enforces the real
// boundary; this is presentation only.
const ENTERTAINMENT_PROVIDER_ALLOWED_PAGES = ['entertainment-admin.html', 'account.html', 'change-password.html', 'help.html'];

(async () => {
  try {
    const response = await fetch('/api/auth/me');
    if (!response.ok) return;
    const user = await response.json();
    if (user.role !== 'entertainmentProvider') return;

    document.querySelectorAll('.staff-tools-nav a').forEach((link) => {
      const page = link.getAttribute('href').replace(/^\//, '');
      if (!ENTERTAINMENT_PROVIDER_ALLOWED_PAGES.includes(page)) link.remove();
    });
  } catch {
    // Best-effort presentation trim — if this fails, the nav just stays
    // full and the server-side checks still apply when a link is clicked.
  }
})();
