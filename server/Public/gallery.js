function escapeHtmlGallery(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function loadGallery() {
  const statusEl = document.getElementById('gallery-status');
  const gridEl = document.getElementById('gallery-grid');
  const photos = [];

  try {
    const menuResponse = await fetch('/api/menu');
    if (menuResponse.ok) {
      const menu = await menuResponse.json();
      const seen = new Set();
      (menu.categories || []).forEach((category) => {
        (category.items || []).forEach((item) => {
          (item.images || []).forEach((src) => {
            if (seen.has(src)) return;
            seen.add(src);
            photos.push({ src, caption: item.name });
          });
        });
      });
    }
  } catch {
    // menu photos are best-effort
  }

  try {
    const placesResponse = await fetch('/api/places-photos');
    if (placesResponse.ok) {
      const places = await placesResponse.json();
      places.forEach((photo) => {
        photos.push({
          src: photo.url,
          caption: photo.attributionName ? `Photo by ${photo.attributionName}` : 'Ohana Belltown',
        });
      });
    }
  } catch {
    // places photos are best-effort
  }

  if (!photos.length) {
    statusEl.textContent = 'No photos to show yet — check back soon.';
    return;
  }

  statusEl.hidden = true;
  gridEl.innerHTML = photos
    .map(
      (photo) => `
        <button type="button" class="gallery-item" data-src="${escapeHtmlGallery(photo.src)}" data-caption="${escapeHtmlGallery(photo.caption)}">
          <img src="${escapeHtmlGallery(photo.src)}" alt="${escapeHtmlGallery(photo.caption)}" loading="lazy" />
        </button>
      `
    )
    .join('');

  gridEl.querySelectorAll('.gallery-item').forEach((el) => {
    el.addEventListener('click', () => {
      window.openLightbox(el.dataset.src, el.dataset.caption);
    });
  });
}

loadGallery();
