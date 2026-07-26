(async () => {
  const el = document.getElementById('edit-menu-link');
  if (!el) return;
  try {
    const response = await fetch('/api/auth/me');
    if (response.ok) {
      el.hidden = false;
    }
  } catch {
    // stay hidden
  }
})();
