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
    }
  } catch {
    // leave the "Log In" link as-is
  }
})();
