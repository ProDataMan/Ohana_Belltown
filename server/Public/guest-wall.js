// The guest photo wall: approved bonus-punch dish photos that the guest
// agreed could be shown and staff ticked "Post on page" for (Loyalty page).
// Fills any [data-guest-wall] section; stays hidden when there are none.
(async () => {
  const sections = document.querySelectorAll('[data-guest-wall]');
  if (!sections.length) return;
  let photos = [];
  try {
    const response = await fetch('/api/guest-photos');
    if (response.ok) photos = await response.json();
  } catch {}
  if (!photos.length) return;
  const esc = (value) => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  const sized = (url) => (url.startsWith('/uploads/') ? `${url}?w=480` : url);
  sections.forEach((section) => {
    section.innerHTML = `
      <div class="panel">
        <h2>From Our Guests</h2>
        <p>Photos shared by guests. Post yours and tag <strong>@ohanabelltown</strong>, then <a href="/rewards">send it to us for a bonus punch</a>.</p>
        <div class="guest-wall">
          ${photos
            .map(
              (p) => `
            <button type="button" class="guest-wall-photo" data-full="${esc(p.url)}" data-caption="${esc(p.dish ? `${p.dish}, shared by a guest` : 'Shared by a guest')}">
              <img src="${esc(sized(p.url))}" alt="${esc(p.dish ? `${p.dish}, shared by a guest` : 'A dish shared by a guest')}" loading="lazy" />
              ${p.dish ? `<span>${esc(p.dish)}</span>` : ''}
            </button>
          `
            )
            .join('')}
        </div>
      </div>
    `;
    section.hidden = false;
    section.querySelectorAll('.guest-wall-photo').forEach((btn) => {
      btn.addEventListener('click', () => window.openLightbox && window.openLightbox(btn.dataset.full, btn.dataset.caption));
    });
  });
})();
