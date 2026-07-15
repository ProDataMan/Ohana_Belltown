document.getElementById('nav-toggle')?.addEventListener('click', () => {
  document.getElementById('site-nav')?.classList.toggle('open');
});

document.querySelectorAll('.nav-dropdown-toggle').forEach((btn) => {
  btn.addEventListener('click', () => {
    btn.parentElement?.classList.toggle('open');
  });
});
