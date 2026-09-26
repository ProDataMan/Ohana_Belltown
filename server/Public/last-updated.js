// The homepage's "Site last updated" corner link — everyone sees the date,
// but only a logged-in staff member gets sent to the actual README on
// GitHub; every other visitor stays on-site at /faq (the public help page).
// Defaults to /faq in the markup itself, so a visitor never sees a broken
// or unstyled link while this check is in flight.
(async () => {
  const badge = document.getElementById('last-updated-badge');
  if (!badge) return;
  try {
    const response = await fetch('/api/auth/me');
    if (response.ok) {
      badge.href = 'https://github.com/ProDataMan/Ohana_Belltown/blob/main/README.md';
      badge.target = '_blank';
      badge.rel = 'noopener';
    }
  } catch {
    // leave it pointed at /faq
  }
})();
