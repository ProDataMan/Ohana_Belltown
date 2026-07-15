const menuContainer = document.getElementById('menu');

let itemsByIndex = [];
let googlePhotosCache = null;

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

function renderControls(categories) {
  if (categories.length < 2) return;

  const controls = document.createElement('div');
  controls.className = 'menu-controls';
  controls.innerHTML = `
    <input type="search" class="menu-search" id="menu-search" placeholder="Search this menu..." />
    <div class="menu-jump">
      ${categories.map((c) => `<a href="#cat-${slugify(c.name)}">${escapeHtml(c.name)}</a>`).join('')}
    </div>
  `;
  menuContainer.before(controls);

  document.getElementById('menu-search').addEventListener('input', (event) => {
    filterMenu(event.target.value.trim().toLowerCase());
  });
}

function filterMenu(query) {
  const categories = menuContainer.querySelectorAll('.category');
  let anyVisible = false;

  categories.forEach((category) => {
    const items = category.querySelectorAll('.item');
    let categoryHasMatch = false;

    items.forEach((item) => {
      const haystack = item.dataset.search || '';
      const matches = !query || haystack.includes(query);
      item.classList.toggle('item-hidden', !matches);
      if (matches) categoryHasMatch = true;
    });

    category.classList.toggle('category-hidden', !categoryHasMatch);
    if (categoryHasMatch) anyVisible = true;
  });

  let noResults = menuContainer.querySelector('.no-results');
  if (!anyVisible) {
    if (!noResults) {
      noResults = document.createElement('p');
      noResults.className = 'error no-results';
      noResults.textContent = 'No items match your search.';
      menuContainer.appendChild(noResults);
    }
  } else if (noResults) {
    noResults.remove();
  }
}

function injectMenuSchema(categories) {
  const existing = document.getElementById('menu-schema');
  if (existing) existing.remove();

  const schema = {
    '@context': 'https://schema.org',
    '@type': 'Menu',
    hasMenuSection: categories.map((category) => ({
      '@type': 'MenuSection',
      name: category.name,
      hasMenuItem: (category.items || []).map((item) => {
        const menuItem = {
          '@type': 'MenuItem',
          name: item.name,
        };
        if (item.description) menuItem.description = item.description;
        if (item.price != null) {
          menuItem.offers = {
            '@type': 'Offer',
            price: item.price,
            priceCurrency: 'USD',
          };
        }
        return menuItem;
      }),
    })),
  };

  const script = document.createElement('script');
  script.type = 'application/ld+json';
  script.id = 'menu-schema';
  script.textContent = JSON.stringify(schema);
  document.head.appendChild(script);
}

function renderMenu(data) {
  const categories = (data.categories || []).filter((c) => c.section === window.MENU_SECTION);

  if (!categories.length) {
    menuContainer.innerHTML = '<p class="error">No menu items were found.</p>';
    return;
  }

  itemsByIndex = [];

  menuContainer.innerHTML = categories
    .map((category) => {
      const noteMarkup = category.note ? `<p class="category-note">${escapeHtml(category.note)}</p>` : '';
      const itemMarkup = (category.items || [])
        .map((item) => {
          const index = itemsByIndex.length;
          itemsByIndex.push({ item, categoryName: category.name });

          const priceMarkup = item.price != null ? `<div class="price">$${Number(item.price).toFixed(2)}</div>` : '';
          const imageMarkup = item.image
            ? `<img class="item-photo" src="${escapeHtml(item.image)}" alt="${escapeHtml(item.name)}" loading="lazy" />`
            : '';
          const searchText = `${item.name} ${item.description || ''}`.toLowerCase();
          return `
            <article class="item" data-search="${escapeHtml(searchText)}" data-index="${index}">
              ${imageMarkup}
              <div class="item-body">
                <h3>${escapeHtml(item.name)}</h3>
                ${item.description ? `<p>${escapeHtml(item.description)}</p>` : ''}
              </div>
              ${priceMarkup}
            </article>
          `;
        })
        .join('');

      return `
        <section class="category" id="cat-${slugify(category.name)}">
          <h2>${escapeHtml(category.name)}</h2>
          ${noteMarkup}
          <div class="items">${itemMarkup}</div>
        </section>
      `;
    })
    .join('');

  renderControls(categories);
  injectMenuSchema(categories);
}

function ensureItemModal() {
  let modal = document.getElementById('item-modal-overlay');
  if (modal) return modal;

  modal = document.createElement('div');
  modal.id = 'item-modal-overlay';
  modal.className = 'item-modal-overlay';
  modal.hidden = true;
  modal.innerHTML = `
    <div class="item-modal">
      <button type="button" class="item-modal-close" aria-label="Close">&times;</button>
      <img class="item-modal-photo" src="" alt="" hidden />
      <p class="item-modal-category"></p>
      <h3 class="item-modal-name"></h3>
      <div class="item-modal-price"></div>
      <p class="item-modal-desc"></p>
      <div class="item-modal-google-section" hidden>
        <p class="item-modal-google-label">More photos from our Google page (general restaurant photos, not necessarily this dish):</p>
        <div class="item-modal-google-strip"></div>
      </div>
    </div>
  `;
  document.body.appendChild(modal);

  modal.addEventListener('click', (event) => {
    if (event.target === modal) closeItemModal();
  });
  modal.querySelector('.item-modal-close').addEventListener('click', closeItemModal);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeItemModal();
  });

  return modal;
}

function closeItemModal() {
  const modal = document.getElementById('item-modal-overlay');
  if (modal) modal.hidden = true;
}

async function loadGooglePhotosOnce() {
  if (googlePhotosCache) return googlePhotosCache;
  try {
    const response = await fetch('/api/places-photos');
    googlePhotosCache = response.ok ? await response.json() : [];
  } catch {
    googlePhotosCache = [];
  }
  return googlePhotosCache;
}

async function openItemModal(index) {
  const entry = itemsByIndex[index];
  if (!entry) return;
  const { item, categoryName } = entry;
  const modal = ensureItemModal();

  modal.querySelector('.item-modal-category').textContent = categoryName;
  modal.querySelector('.item-modal-name').textContent = item.name;
  modal.querySelector('.item-modal-desc').textContent = item.description || '';

  const priceEl = modal.querySelector('.item-modal-price');
  priceEl.textContent = item.price != null ? `$${Number(item.price).toFixed(2)}` : '';
  priceEl.hidden = item.price == null;

  const photoEl = modal.querySelector('.item-modal-photo');
  if (item.image) {
    photoEl.src = item.image;
    photoEl.alt = item.name;
    photoEl.hidden = false;
    photoEl.onclick = () => window.openLightbox(item.image, item.name);
  } else {
    photoEl.hidden = true;
  }

  modal.hidden = false;

  const googleSection = modal.querySelector('.item-modal-google-section');
  const strip = modal.querySelector('.item-modal-google-strip');
  const photos = await loadGooglePhotosOnce();
  if (photos.length) {
    googleSection.hidden = false;
    strip.innerHTML = photos
      .map(
        (p) =>
          `<img src="${escapeHtml(p.url)}" alt="Photo of Ohana Belltown from Google Maps" loading="lazy" data-full="${escapeHtml(p.url)}" data-caption="Photo by ${escapeHtml(p.attributionName)}, via Google" />`
      )
      .join('');
    strip.querySelectorAll('img').forEach((imgEl) => {
      imgEl.addEventListener('click', () => window.openLightbox(imgEl.dataset.full, imgEl.dataset.caption));
    });
  } else {
    googleSection.hidden = true;
  }
}

menuContainer.addEventListener('click', (event) => {
  const photo = event.target.closest('.item-photo');
  if (photo) {
    window.openLightbox(photo.src, photo.alt);
    return;
  }
  const itemEl = event.target.closest('.item');
  if (itemEl && itemEl.dataset.index != null) {
    openItemModal(Number(itemEl.dataset.index));
  }
});

async function loadMenu() {
  try {
    const response = await fetch('/api/menu');
    if (!response.ok) {
      throw new Error('Unable to load the menu data.');
    }

    const data = await response.json();
    renderMenu(data);
  } catch (error) {
    menuContainer.innerHTML = `<p class="error">${escapeHtml(error.message)}</p>`;
  }
}

loadMenu();
