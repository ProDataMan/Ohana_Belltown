const menuContainer = document.getElementById('menu');

const TAG_LABELS = {
  vegetarian: 'Vegetarian',
  'gluten-free-available': 'GF available',
  shellfish: 'Shellfish',
  fish: 'Fish',
  peanuts: 'Peanuts',
  egg: 'Egg',
  soy: 'Soy',
  wheat: 'Wheat',
  corn: 'Corn',
  sesame: 'Sesame',
  dairy: 'Dairy',
  raw: 'Raw/undercooked',
};

let itemsByIndex = [];
let googlePhotosCache = null;
let activeTagFilter = null;

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/// A `?table=` on the URL means the visitor scanned that table's QR code.
/// Stashed in sessionStorage so it survives clicking to another menu page
/// (e.g. Happy Hour's "Full Menu" link) without every internal link needing
/// to carry the query param — cleared automatically when the tab closes.
function getTableId() {
  const fromQuery = new URLSearchParams(window.location.search).get('table');
  if (fromQuery) {
    sessionStorage.setItem('ohana_table_id', fromQuery);
    return fromQuery;
  }
  return sessionStorage.getItem('ohana_table_id');
}

/// Orders placed this session that haven't been marked received yet, keyed
/// by item name — lets the "Order" button turn into "Mark Received" and
/// stay that way across a re-render (e.g. navigating to another menu page).
function getActiveOrders() {
  try {
    return JSON.parse(sessionStorage.getItem('ohana_active_orders') || '{}');
  } catch {
    return {};
  }
}

function setActiveOrder(itemName, orderId) {
  const active = getActiveOrders();
  active[itemName] = orderId;
  sessionStorage.setItem('ohana_active_orders', JSON.stringify(active));
}

function clearActiveOrder(itemName) {
  const active = getActiveOrders();
  delete active[itemName];
  sessionStorage.setItem('ohana_active_orders', JSON.stringify(active));
}

async function placeTableOrder(button) {
  const tableId = getTableId();
  if (!tableId) return;
  const itemName = button.dataset.itemName;
  const itemId = button.dataset.itemId || null;
  const articleEl = button.closest('.item');
  const modifierCheckboxes = articleEl ? Array.from(articleEl.querySelectorAll('.item-modifiers input')) : [];
  const modifiers = modifierCheckboxes.filter((cb) => cb.checked).map((cb) => cb.dataset.modifierName);
  button.disabled = true;
  button.textContent = 'Sending...';
  try {
    const response = await fetch('/api/table-orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tableId, itemName, itemId, section: window.MENU_SECTION, modifiers }),
    });
    if (!response.ok) throw new Error();
    const entry = await response.json();
    setActiveOrder(itemName, entry.id);
    button.dataset.orderId = entry.id;
    button.textContent = 'Mark Received';
    button.classList.add('order-btn-active');
    button.disabled = false;
    modifierCheckboxes.forEach((cb) => { cb.disabled = true; });
  } catch {
    button.textContent = 'Failed — tap to retry';
    button.disabled = false;
  }
}

async function markOrderDelivered(button) {
  const orderId = button.dataset.orderId;
  const itemName = button.dataset.itemName;
  const articleEl = button.closest('.item');
  button.disabled = true;
  button.textContent = 'Confirming...';
  try {
    const response = await fetch(`/api/table-orders/${encodeURIComponent(orderId)}/deliver`, { method: 'POST' });
    if (!response.ok) throw new Error();
    clearActiveOrder(itemName);
    delete button.dataset.orderId;
    button.textContent = 'Order';
    button.classList.remove('order-btn-active');
    button.disabled = false;
    if (articleEl) {
      articleEl.querySelectorAll('.item-modifiers input').forEach((cb) => {
        cb.disabled = false;
        cb.checked = false;
      });
    }
  } catch {
    button.textContent = 'Failed — tap to retry';
    button.disabled = false;
  }
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

function renderControls(categories) {
  const usedTags = new Set();
  categories.forEach((c) => (c.items || []).forEach((it) => (it.tags || []).forEach((t) => usedTags.add(t))));

  if (categories.length < 2 && !usedTags.size) return;

  const controls = document.createElement('div');
  controls.className = 'menu-controls';
  controls.innerHTML = `
    <input type="search" class="menu-search" id="menu-search" placeholder="Search this menu..." />
    ${
      categories.length > 1
        ? `<div class="menu-jump">${categories.map((c) => `<a href="#cat-${slugify(c.name)}">${escapeHtml(c.name)}</a>`).join('')}</div>`
        : ''
    }
    ${
      usedTags.size
        ? `<div class="tag-filter-chips">
            ${Array.from(usedTags)
              .map((t) => `<button type="button" class="tag-chip" data-tag="${escapeHtml(t)}">${escapeHtml(TAG_LABELS[t] || t)}</button>`)
              .join('')}
          </div>`
        : ''
    }
  `;
  menuContainer.before(controls);

  document.getElementById('menu-search').addEventListener('input', (event) => {
    filterMenu(event.target.value.trim().toLowerCase());
  });

  controls.querySelectorAll('.tag-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      const tag = chip.dataset.tag;
      activeTagFilter = activeTagFilter === tag ? null : tag;
      controls.querySelectorAll('.tag-chip').forEach((c) => c.classList.toggle('active', c.dataset.tag === activeTagFilter));
      filterMenu(document.getElementById('menu-search').value.trim().toLowerCase());
    });
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
      const matchesQuery = !query || haystack.includes(query);
      const itemTags = (item.dataset.tags || '').split(',').filter(Boolean);
      const matchesTag = !activeTagFilter || itemTags.includes(activeTagFilter);
      const matches = matchesQuery && matchesTag;
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
  const tableId = getTableId();
  const activeOrders = tableId ? getActiveOrders() : {};

  menuContainer.innerHTML = categories
    .map((category) => {
      const noteMarkup = category.note ? `<p class="category-note">${escapeHtml(category.note)}</p>` : '';
      const itemMarkup = (category.items || [])
        .map((item) => {
          const index = itemsByIndex.length;
          itemsByIndex.push({ item, categoryName: category.name });

          const priceMarkup = item.price != null ? `<div class="price">$${Number(item.price).toFixed(2)}</div>` : '';
          const featuredImage = (item.images || [])[0];
          const imageMarkup = featuredImage
            ? `<img class="item-photo" src="${escapeHtml(featuredImage)}" alt="${escapeHtml(item.name)}" loading="lazy" />`
            : '';
          const searchText = `${item.name} ${item.description || ''}`.toLowerCase();
          const tags = item.tags || [];
          const tagsMarkup = tags.length
            ? `<div class="item-tags">${tags.map((t) => `<span class="item-tag-badge">${escapeHtml(TAG_LABELS[t] || t)}</span>`).join('')}</div>`
            : '';
          const specialBadge = item.featured ? '<span class="special-badge">&#9733; Today\'s Special</span>' : '';
          const soldOut = item.available === false;
          const soldOutBadge = soldOut ? '<span class="sold-out-badge">Sold Out Today</span>' : '';
          const editLink = item.id
            ? `<a class="staff-edit-link" href="/edit-item.html?id=${encodeURIComponent(item.id)}" hidden>Edit</a>`
            : '';
          const activeOrderId = activeOrders[item.name];
          const orderButton =
            tableId && !soldOut
              ? `<button type="button" class="order-btn${activeOrderId ? ' order-btn-active' : ''}" data-item-name="${escapeHtml(item.name)}" data-item-id="${escapeHtml(item.id || '')}"${activeOrderId ? ` data-order-id="${escapeHtml(activeOrderId)}"` : ''}>${activeOrderId ? 'Mark Received' : 'Order'}</button>`
              : '';
          const modifiers = item.modifiers || [];
          const modifiersMarkup =
            tableId && !soldOut && modifiers.length
              ? `<div class="item-modifiers">
                  ${modifiers
                    .map(
                      (m) => `
                    <label class="item-modifier-checkbox">
                      <input type="checkbox" data-modifier-name="${escapeHtml(m.name)}" ${activeOrderId ? 'disabled' : ''} />
                      ${escapeHtml(m.name)} (+$${Number(m.priceDelta).toFixed(2)})
                    </label>
                  `
                    )
                    .join('')}
                </div>`
              : '';
          return `
            <article class="item${soldOut ? ' item-sold-out' : ''}" data-search="${escapeHtml(searchText)}" data-index="${index}" data-tags="${escapeHtml(tags.join(','))}">
              ${imageMarkup}
              <div class="item-body">
                ${soldOutBadge}${specialBadge}
                <h3>${escapeHtml(item.name)}</h3>
                ${item.description ? `<p>${escapeHtml(item.description)}</p>` : ''}
                ${tagsMarkup}
                ${modifiersMarkup}
              </div>
              ${priceMarkup}
              ${orderButton}
              ${editLink}
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
      <div class="item-modal-gallery" hidden></div>
      <p class="item-modal-category"></p>
      <span class="sold-out-badge item-modal-sold-out" hidden>Sold Out Today</span>
      <h3 class="item-modal-name"></h3>
      <div class="item-modal-price"></div>
      <p class="item-modal-desc"></p>
      <div class="item-tags item-modal-tags"></div>
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

let galleryRotationInterval = null;

function closeItemModal() {
  const modal = document.getElementById('item-modal-overlay');
  if (modal) modal.hidden = true;
  if (galleryRotationInterval) {
    clearInterval(galleryRotationInterval);
    galleryRotationInterval = null;
  }
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

  fetch('/api/analytics/item-view', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: item.name }),
  }).catch(() => {});

  modal.querySelector('.item-modal-category').textContent = categoryName;
  modal.querySelector('.item-modal-sold-out').hidden = item.available !== false;
  modal.querySelector('.item-modal-name').textContent = item.name;
  modal.querySelector('.item-modal-desc').textContent = item.description || '';

  const priceEl = modal.querySelector('.item-modal-price');
  priceEl.textContent = item.price != null ? `$${Number(item.price).toFixed(2)}` : '';
  priceEl.hidden = item.price == null;

  const tagsEl = modal.querySelector('.item-modal-tags');
  const tags = item.tags || [];
  tagsEl.innerHTML = tags.map((t) => `<span class="item-tag-badge">${escapeHtml(TAG_LABELS[t] || t)}</span>`).join('');

  if (galleryRotationInterval) {
    clearInterval(galleryRotationInterval);
    galleryRotationInterval = null;
  }

  const gallery = modal.querySelector('.item-modal-gallery');
  const images = item.images || [];
  if (images.length) {
    gallery.hidden = false;
    gallery.innerHTML = images
      .map(
        (src, i) =>
          `<img class="item-modal-gallery-img${i === 0 ? ' active' : ''}" src="${escapeHtml(src)}" alt="${escapeHtml(item.name)}" loading="lazy" />`
      )
      .join('');
    const imgs = gallery.querySelectorAll('img');
    imgs.forEach((imgEl) => {
      imgEl.addEventListener('click', () => window.openLightbox(imgEl.src, item.name));
    });
    if (imgs.length > 1) {
      let current = 0;
      galleryRotationInterval = setInterval(() => {
        imgs[current].classList.remove('active');
        current = (current + 1) % imgs.length;
        imgs[current].classList.add('active');
      }, 4000);
    }
  } else {
    gallery.hidden = true;
    gallery.innerHTML = '';
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
  const orderBtn = event.target.closest('.order-btn');
  if (orderBtn) {
    if (orderBtn.dataset.orderId) {
      markOrderDelivered(orderBtn);
    } else {
      placeTableOrder(orderBtn);
    }
    return;
  }
  if (event.target.closest('.staff-edit-link')) {
    return;
  }
  if (event.target.closest('.item-modifiers')) {
    return;
  }
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

async function revealStaffEditLinksIfLoggedIn() {
  const links = document.querySelectorAll('.staff-edit-link');
  if (!links.length) return;
  try {
    const response = await fetch('/api/auth/me');
    if (response.ok) {
      links.forEach((link) => { link.hidden = false; });
    }
  } catch {
    // stay hidden
  }
}

async function loadMenu() {
  try {
    const response = await fetch('/api/menu');
    if (!response.ok) {
      throw new Error('Unable to load the menu data.');
    }

    const data = await response.json();
    renderMenu(data);
    revealStaffEditLinksIfLoggedIn();
  } catch (error) {
    menuContainer.innerHTML = `<p class="error">${escapeHtml(error.message)}</p>`;
  }
}

loadMenu();
