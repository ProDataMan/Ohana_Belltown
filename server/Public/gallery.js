function escapeHtmlGallery(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// A menu category's own `section` (menu/sushi/happy_hour/drinks) is the
// source of truth for food vs. drinks — except happy_hour bundles a
// "Drinks" category alongside food ones, so a name check catches that case
// too. Google Places photos aren't tied to a dish at all (they're whatever
// guests or Google happened to shoot), so they land under "atmosphere"
// rather than being guessed at.
function categoryBucketFor(menuCategory) {
  const isDrinks = menuCategory.section === 'drinks' || /drink/i.test(menuCategory.name || '');
  return isDrinks ? 'drinks' : 'food';
}

let allPhotos = [];
let activeCategory = 'all';

function renderGallery() {
  const gridEl = document.getElementById('gallery-grid');
  const visible = activeCategory === 'all' ? allPhotos : allPhotos.filter((p) => p.category === activeCategory);

  if (!visible.length) {
    gridEl.innerHTML = '';
    document.getElementById('gallery-status').hidden = false;
    document.getElementById('gallery-status').textContent = 'No photos in this category yet.';
    return;
  }
  document.getElementById('gallery-status').hidden = true;

  gridEl.innerHTML = visible
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

document.getElementById('gallery-tabs').addEventListener('click', (event) => {
  const btn = event.target.closest('.tag-chip');
  if (!btn) return;
  activeCategory = btn.dataset.category;
  document.querySelectorAll('#gallery-tabs .tag-chip').forEach((chip) => {
    chip.classList.toggle('active', chip === btn);
  });
  renderGallery();
});

async function loadGallery() {
  const statusEl = document.getElementById('gallery-status');

  try {
    const menuResponse = await fetch('/api/menu');
    if (menuResponse.ok) {
      const menu = await menuResponse.json();
      const seen = new Set();
      (menu.categories || []).forEach((category) => {
        const bucket = categoryBucketFor(category);
        (category.items || []).forEach((item) => {
          (item.images || []).forEach((src) => {
            if (seen.has(src)) return;
            seen.add(src);
            allPhotos.push({ src, caption: item.name, category: bucket });
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
        allPhotos.push({
          src: photo.url,
          caption: photo.attributionName ? `Photo by ${photo.attributionName}` : 'Ohana Belltown',
          category: 'atmosphere',
        });
      });
    }
  } catch {
    // places photos are best-effort
  }

  if (!allPhotos.length) {
    statusEl.textContent = 'No photos to show yet — check back soon.';
    return;
  }

  renderGallery();
}

loadGallery();
