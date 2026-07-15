function escapeHtmlPP(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadPlacesPhotos() {
  const container = document.getElementById('places-photos');
  if (!container) return;

  try {
    const response = await fetch('/api/places-photos');
    if (!response.ok) throw new Error('Unable to load photos.');
    const photos = await response.json();
    if (!photos.length) {
      container.closest('.content-section')?.remove();
      return;
    }

    let current = 0;
    container.innerHTML = photos
      .map(
        (p, i) => `
          <figure class="places-photo-slide${i === 0 ? ' active' : ''}">
            <img src="${escapeHtmlPP(p.url)}" alt="Photo of Ohana Belltown from Google Maps" loading="lazy" />
            <figcaption>
              Photo by
              ${p.attributionUrl ? `<a href="${escapeHtmlPP(p.attributionUrl)}" target="_blank" rel="noopener">${escapeHtmlPP(p.attributionName)}</a>` : escapeHtmlPP(p.attributionName)}
              via Google
            </figcaption>
          </figure>
        `
      )
      .join('');

    if (photos.length > 1) {
      setInterval(() => {
        const slides = container.querySelectorAll('.places-photo-slide');
        slides[current].classList.remove('active');
        current = (current + 1) % slides.length;
        slides[current].classList.add('active');
      }, 5000);
    }
  } catch (error) {
    container.closest('.content-section')?.remove();
  }
}

loadPlacesPhotos();
