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
// Set once the logged-in-staff check resolves — staff previewing their own
// edits need to see prices too, same as the Edit links they already get.
let staffLoggedIn = false;

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

/// Items a guest has picked but not yet sent to staff — keyed by item name,
/// same as active orders. Lets someone add a sushi roll, then navigate to
/// Drinks and add a cocktail, then send everything as one order from
/// wherever they end up. Cleared once the order is actually sent.
function getPendingCart() {
  try {
    return JSON.parse(sessionStorage.getItem('ohana_pending_cart') || '{}');
  } catch {
    return {};
  }
}

function setPendingCartItem(itemName, entry) {
  const cart = getPendingCart();
  cart[itemName] = entry;
  sessionStorage.setItem('ohana_pending_cart', JSON.stringify(cart));
  return cart;
}

function removePendingCartItem(itemName) {
  const cart = getPendingCart();
  delete cart[itemName];
  sessionStorage.setItem('ohana_pending_cart', JSON.stringify(cart));
  return cart;
}

function clearPendingCart() {
  sessionStorage.removeItem('ohana_pending_cart');
}

// The same item can have an order button on both the menu list (.item) and
// in the item-detail modal (.item-modal-overlay) at once — these find every
// instance of a given item's controls so an action taken in either place
// (e.g. adding to cart from the modal) is reflected in the other right away.
function findOrderButtons(itemName) {
  return Array.from(document.querySelectorAll(`.order-btn[data-item-name="${CSS.escape(itemName)}"]`));
}

function findItemContainers(itemName) {
  return findOrderButtons(itemName)
    .map((btn) => btn.closest('.item') || btn.closest('.item-modal-overlay'))
    .filter(Boolean);
}

// Adding an item no longer sends it right away — it just joins the pending
// cart (see sendPendingOrder) so a guest can pick several things across
// however many menu pages before staff are actually notified once.
function addItemToCart(button) {
  const itemName = button.dataset.itemName;
  const itemId = button.dataset.itemId || null;
  const ownContainer = button.closest('.item') || button.closest('.item-modal-overlay');
  const modifierCheckboxes = ownContainer ? Array.from(ownContainer.querySelectorAll('.item-modifiers input')) : [];
  const modifiers = modifierCheckboxes.filter((cb) => cb.checked).map((cb) => cb.dataset.modifierName);

  // Some items (e.g. Extra Sauces — all checkboxes, no meaningful base
  // price) require at least one modifier checked before they can be
  // ordered at all — refuses silently rather than sending a $0 order.
  const modifiersContainer = ownContainer ? ownContainer.querySelector('.item-modifiers') : null;
  if (modifiersContainer && modifiersContainer.dataset.requiresSelection === 'true') {
    const errorEl = modifiersContainer.querySelector('.item-modifiers-error');
    if (!modifiers.length) {
      if (errorEl) errorEl.hidden = false;
      return;
    }
    if (errorEl) errorEl.hidden = true;
  }

  // Required choice groups (e.g. Shogun Bento's choice of protein) must
  // each have a selection before this can be added — refuses silently
  // rather than sending an order the kitchen can't act on.
  const choiceGroupEls = ownContainer ? Array.from(ownContainer.querySelectorAll('.item-choice-group')) : [];
  const choiceSelections = [];
  let missingChoice = false;
  choiceGroupEls.forEach((groupEl) => {
    const checked = groupEl.querySelector('input:checked');
    const errorEl = groupEl.querySelector('.item-choice-group-error');
    if (!checked) {
      missingChoice = true;
      if (errorEl) errorEl.hidden = false;
      return;
    }
    if (errorEl) errorEl.hidden = true;
    choiceSelections.push(`${groupEl.dataset.groupLabel}: ${checked.value}`);
  });
  if (missingChoice) return;

  setPendingCartItem(itemName, { itemId, section: window.MENU_SECTION, modifiers: [...modifiers, ...choiceSelections] });

  findOrderButtons(itemName).forEach((btn) => {
    btn.textContent = 'Added — Tap to Remove';
    btn.classList.add('order-btn-in-cart');
  });
  findItemContainers(itemName).forEach((c) => {
    c.querySelectorAll('.item-modifiers input').forEach((cb) => { cb.disabled = true; });
    c.querySelectorAll('.item-choice-group input').forEach((r) => { r.disabled = true; });
  });
  updateCartBadge();
}

function removeItemFromCart(button) {
  const itemName = button.dataset.itemName;
  removePendingCartItem(itemName);

  findOrderButtons(itemName).forEach((btn) => {
    btn.textContent = 'Add to Order';
    btn.classList.remove('order-btn-in-cart');
  });
  findItemContainers(itemName).forEach((c) => {
    c.querySelectorAll('.item-modifiers input').forEach((cb) => { cb.disabled = false; });
    c.querySelectorAll('.item-choice-group input').forEach((r) => { r.disabled = false; });
  });
  updateCartBadge();
}

// Sends every item in the pending cart as its own table order (same
// endpoint as before, just fired together instead of one at a time), then
// flips each item's button straight to "Mark Received" — same end state
// placing them individually always resulted in.
async function sendPendingOrder() {
  const tableId = getTableId();
  const cart = getPendingCart();
  const itemNames = Object.keys(cart);
  if (!tableId || !itemNames.length) return;

  const results = await Promise.all(
    itemNames.map(async (itemName) => {
      const entry = cart[itemName];
      try {
        const response = await fetch('/api/table-orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ tableId, itemName, itemId: entry.itemId, section: entry.section, modifiers: entry.modifiers }),
        });
        if (!response.ok) throw new Error();
        const order = await response.json();
        return { itemName, ok: true, orderId: order.id };
      } catch {
        return { itemName, ok: false };
      }
    })
  );

  results.forEach((result) => {
    if (!result.ok) return;
    setActiveOrder(result.itemName, result.orderId);
    removePendingCartItem(result.itemName);
    findOrderButtons(result.itemName).forEach((btn) => {
      btn.dataset.orderId = result.orderId;
      btn.textContent = 'Mark Received';
      btn.classList.remove('order-btn-in-cart');
      btn.classList.add('order-btn-active');
    });
  });

  updateCartBadge();
  return results;
}

async function markOrderDelivered(button) {
  const orderId = button.dataset.orderId;
  const itemName = button.dataset.itemName;
  button.disabled = true;
  button.textContent = 'Confirming...';
  try {
    const response = await fetch(`/api/table-orders/${encodeURIComponent(orderId)}/deliver`, { method: 'POST' });
    if (!response.ok) throw new Error();
    clearActiveOrder(itemName);
    findOrderButtons(itemName).forEach((btn) => {
      delete btn.dataset.orderId;
      btn.textContent = 'Add to Order';
      btn.classList.remove('order-btn-active');
      btn.disabled = false;
    });
    findItemContainers(itemName).forEach((c) => {
      c.querySelectorAll('.item-modifiers input').forEach((cb) => {
        cb.disabled = false;
        cb.checked = false;
      });
      c.querySelectorAll('.item-choice-group input').forEach((r) => {
        r.disabled = false;
        r.checked = false;
      });
    });
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

function injectMenuSchema(categories, tableId) {
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
        // Same rule as the visible price: only include it in the page's
        // structured data (what search engines index) when a table's QR
        // code has actually been scanned — otherwise it'd leak into search
        // results even with prices hidden on the page itself.
        if (item.price != null && tableId) {
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

// Shared between the inline card and the detail modal, so a change to one
// doesn't quietly drift from the other. Returns just the inner content of
// the `.item-modifiers` wrapper (checkboxes + an optional "must pick one"
// error message) — the wrapper itself carries `data-requires-selection`
// so addItemToCart knows whether to enforce it.
function renderModifiersInnerMarkup(item, orderLocked) {
  const modifiers = item.modifiers || [];
  const checkboxesMarkup = modifiers
    .map(
      (m) => `
    <label class="item-modifier-checkbox">
      <input type="checkbox" data-modifier-name="${escapeHtml(m.name)}" data-modifier-price="${m.priceDelta}" ${orderLocked ? 'disabled' : ''} />
      ${escapeHtml(m.name)} (+$${Number(m.priceDelta).toFixed(2)})
    </label>
  `
    )
    .join('');
  const errorMarkup = item.requiresModifierSelection
    ? '<p class="item-modifiers-error" hidden>Please select at least one.</p>'
    : '';
  return checkboxesMarkup + errorMarkup;
}

// A required, mutually-exclusive choice bundled into one dish (e.g. Shogun
// Bento's "your choice of chicken or beef teriyaki") — radio buttons, not
// checkboxes, since exactly one option must be picked and none of them
// change the price. `namePrefix` keeps each rendered instance's radio
// `name` attributes from colliding with the same item shown elsewhere on
// the page (e.g. both the inline card and the detail modal at once).
function renderChoiceGroupsMarkup(item, tableId, soldOut, orderLocked, namePrefix) {
  const groups = item.choiceGroups || [];
  if (soldOut || !groups.length) return '';
  return `
    <div class="item-choice-groups staff-revealable-extras" ${tableId ? '' : 'hidden'}>
      ${groups
        .map(
          (g) => `
        <div class="item-choice-group" data-group-id="${escapeHtml(g.id)}" data-group-label="${escapeHtml(g.label)}">
          <p class="item-choice-group-label">${escapeHtml(g.label)}</p>
          ${g.options
            .map(
              (option) => `
            <label class="item-choice-option">
              <input type="radio" name="choice-${escapeHtml(namePrefix)}-${escapeHtml(g.id)}" value="${escapeHtml(option)}" ${orderLocked ? 'disabled' : ''} />
              ${escapeHtml(option)}
            </label>
          `
            )
            .join('')}
          <p class="item-choice-group-error" hidden>Please make a selection.</p>
        </div>
      `
        )
        .join('')}
    </div>
  `;
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
  const pendingCart = tableId ? getPendingCart() : {};

  menuContainer.innerHTML = categories
    .map((category) => {
      const noteMarkup = category.note ? `<p class="category-note">${escapeHtml(category.note)}</p>` : '';
      const itemMarkup = (category.items || [])
        .map((item) => {
          const index = itemsByIndex.length;
          itemsByIndex.push({ item, categoryName: category.name });

          // Prices only show once a table's QR code has been scanned this
          // session (Yosh's call — browsing the public site shouldn't show
          // prices at all, only ordering from an actual table). Rendered
          // hidden rather than omitted so logged-in staff can still reveal
          // it (see revealStaffOnlyElementsIfLoggedIn) to check their edits.
          const priceMarkup =
            item.price != null
              ? `<div class="price staff-revealable-price" data-base-price="${item.price}" ${tableId ? '' : 'hidden'}>$${Number(item.price).toFixed(2)}</div>`
              : '';
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
          const inCart = !activeOrderId && Boolean(pendingCart[item.name]);
          const orderLocked = Boolean(activeOrderId) || inCart;
          let orderBtnClass = 'order-btn';
          let orderBtnLabel = 'Add to Order';
          if (activeOrderId) {
            orderBtnClass = 'order-btn order-btn-active';
            orderBtnLabel = 'Mark Received';
          } else if (inCart) {
            orderBtnClass = 'order-btn order-btn-in-cart';
            orderBtnLabel = 'Added — Tap to Remove';
          }
          const orderButton =
            tableId && !soldOut
              ? `<button type="button" class="${orderBtnClass}" data-item-name="${escapeHtml(item.name)}" data-item-id="${escapeHtml(item.id || '')}"${activeOrderId ? ` data-order-id="${escapeHtml(activeOrderId)}"` : ''}>${orderBtnLabel}</button>`
              : '';
          const modifiers = item.modifiers || [];
          // Rendered whenever the item has any, not just once a table's QR
          // is scanned — a logged-in staff member previewing the menu
          // should see what add-ons exist here, same as they already see
          // prices (staff-revealable-extras, revealed by
          // revealStaffOnlyElementsIfLoggedIn once login is confirmed).
          const modifiersMarkup =
            !soldOut && modifiers.length
              ? `<div class="item-modifiers staff-revealable-extras" data-requires-selection="${item.requiresModifierSelection ? 'true' : 'false'}" ${tableId ? '' : 'hidden'}>
                  ${renderModifiersInnerMarkup(item, orderLocked)}
                </div>`
              : '';
          const choiceGroupsMarkup = renderChoiceGroupsMarkup(item, tableId, soldOut, orderLocked, `item-${index}`);
          return `
            <article class="item${soldOut ? ' item-sold-out' : ''}" data-search="${escapeHtml(searchText)}" data-index="${index}" data-tags="${escapeHtml(tags.join(','))}">
              ${imageMarkup}
              <div class="item-body">
                ${soldOutBadge}${specialBadge}
                <h3>${escapeHtml(item.name)}</h3>
                ${item.description ? `<p>${escapeHtml(item.description)}</p>` : ''}
                ${tagsMarkup}
                ${modifiersMarkup}
                ${choiceGroupsMarkup}
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
  renderOrderingHint(tableId);
  injectMenuSchema(categories, tableId);
  updateCartBadge();
}

// A one-time orientation for guests actively at a table (tableId set) —
// separate from renderControls, which skips itself entirely on a
// single-category/no-tags menu page and shouldn't gate this too.
function renderOrderingHint(tableId) {
  const existing = document.getElementById('ordering-hint');
  if (existing) existing.remove();
  if (!tableId) return;

  const hint = document.createElement('p');
  hint.id = 'ordering-hint';
  hint.className = 'hint ordering-hint';
  hint.innerHTML =
    'Tap <strong>Add to Order</strong> on anything you\'d like, from any menu page — then tap <strong>Review &amp; Send</strong> (bottom-left) once you\'re done picking.';
  menuContainer.before(hint);
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
      <div class="item-modal-price price"></div>
      <p class="item-modal-desc"></p>
      <div class="item-tags item-modal-tags"></div>
      <div class="item-modifiers item-modal-modifiers" hidden></div>
      <div class="item-modal-choice-groups"></div>
      <button type="button" class="order-btn item-modal-order-btn" hidden></button>
      <div class="item-modal-google-section" hidden>
        <p class="item-modal-google-label"></p>
        <div class="item-modal-google-strip"></div>
      </div>
    </div>
  `;
  document.body.appendChild(modal);

  modal.addEventListener('click', (event) => {
    if (event.target === modal) {
      closeItemModal();
      return;
    }
    const orderBtn = event.target.closest('.order-btn');
    if (orderBtn) {
      if (orderBtn.dataset.orderId) {
        markOrderDelivered(orderBtn);
      } else if (orderBtn.classList.contains('order-btn-in-cart')) {
        removeItemFromCart(orderBtn);
      } else {
        addItemToCart(orderBtn);
      }
    }
  });
  modal.addEventListener('change', (event) => {
    if (event.target.matches('.item-modifiers input')) {
      updateItemPriceDisplay(modal);
      const errorEl = event.target.closest('.item-modifiers')?.querySelector('.item-modifiers-error');
      if (errorEl) errorEl.hidden = true;
      return;
    }
    if (event.target.matches('.item-choice-group input')) {
      const errorEl = event.target.closest('.item-choice-group')?.querySelector('.item-choice-group-error');
      if (errorEl) errorEl.hidden = true;
    }
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
  const showPrice = item.price != null && (Boolean(getTableId()) || staffLoggedIn);
  if (item.price != null) {
    priceEl.dataset.basePrice = item.price;
  } else {
    delete priceEl.dataset.basePrice;
  }
  priceEl.textContent = showPrice ? `$${Number(item.price).toFixed(2)}` : '';
  priceEl.hidden = !showPrice;

  const tagsEl = modal.querySelector('.item-modal-tags');
  const tags = item.tags || [];
  tagsEl.innerHTML = tags.map((t) => `<span class="item-tag-badge">${escapeHtml(TAG_LABELS[t] || t)}</span>`).join('');

  const tableId = getTableId();
  const soldOut = item.available === false;
  const activeOrders = getActiveOrders();
  const pendingCart = getPendingCart();
  const activeOrderId = activeOrders[item.name];
  const inCart = !activeOrderId && Boolean(pendingCart[item.name]);
  const orderLocked = Boolean(activeOrderId) || inCart;

  // Shown whenever the item has any add-ons/choice groups, same as prices
  // above — either a scanned table, or a logged-in staff member previewing
  // the menu. Ordering itself (the button below) still requires a table.
  const canSeeExtras = Boolean(tableId) || staffLoggedIn;

  const modifiersEl = modal.querySelector('.item-modal-modifiers');
  const modifiers = item.modifiers || [];
  if (canSeeExtras && !soldOut && modifiers.length) {
    modifiersEl.hidden = false;
    modifiersEl.dataset.requiresSelection = item.requiresModifierSelection ? 'true' : 'false';
    modifiersEl.innerHTML = renderModifiersInnerMarkup(item, orderLocked);
  } else {
    modifiersEl.hidden = true;
    modifiersEl.innerHTML = '';
    delete modifiersEl.dataset.requiresSelection;
  }

  modal.querySelector('.item-modal-choice-groups').innerHTML = renderChoiceGroupsMarkup(item, canSeeExtras, soldOut, orderLocked, 'modal');

  const orderBtnEl = modal.querySelector('.item-modal-order-btn');
  if (tableId && !soldOut) {
    orderBtnEl.hidden = false;
    orderBtnEl.className = 'order-btn item-modal-order-btn';
    if (activeOrderId) {
      orderBtnEl.classList.add('order-btn-active');
      orderBtnEl.textContent = 'Mark Received';
      orderBtnEl.dataset.orderId = activeOrderId;
    } else if (inCart) {
      orderBtnEl.classList.add('order-btn-in-cart');
      orderBtnEl.textContent = 'Added — Tap to Remove';
      delete orderBtnEl.dataset.orderId;
    } else {
      orderBtnEl.textContent = 'Add to Order';
      delete orderBtnEl.dataset.orderId;
    }
    orderBtnEl.dataset.itemName = item.name;
    orderBtnEl.dataset.itemId = item.id || '';
  } else {
    orderBtnEl.hidden = true;
  }

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

  // With 2+ of its own photos, this dish already has real coverage — show a
  // proper gallery of just those instead of diluting it with generic
  // restaurant photos. Below that, fall back to Google's photos as before,
  // since a bare 0-1-photo item would otherwise have nothing extra to show.
  const googleSection = modal.querySelector('.item-modal-google-section');
  const label = modal.querySelector('.item-modal-google-label');
  const strip = modal.querySelector('.item-modal-google-strip');
  if (images.length >= 2) {
    googleSection.hidden = false;
    label.textContent = 'More photos of this dish:';
    strip.innerHTML = images
      .map(
        (src) => `<img src="${escapeHtml(src)}" alt="${escapeHtml(item.name)}" loading="lazy" data-full="${escapeHtml(src)}" data-caption="${escapeHtml(item.name)}" />`
      )
      .join('');
    strip.querySelectorAll('img').forEach((imgEl) => {
      imgEl.addEventListener('click', () => window.openLightbox(imgEl.dataset.full, imgEl.dataset.caption));
    });
  } else {
    const photos = await loadGooglePhotosOnce();
    if (photos.length) {
      googleSection.hidden = false;
      label.textContent = 'More photos from our Google page (general restaurant photos, not necessarily this dish):';
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
}

// Keeps the displayed price in sync with whichever add-ons are checked, so
// a guest sees the real total (and what's driving it) before they order —
// e.g. "$55.10 ($29.00 + Yosh Size $26.10)".
function updateItemPriceDisplay(articleEl) {
  const priceEl = articleEl.querySelector('.price');
  if (!priceEl || priceEl.dataset.basePrice == null) return;
  const basePrice = Number(priceEl.dataset.basePrice);

  const checked = Array.from(articleEl.querySelectorAll('.item-modifiers input:checked'));
  if (!checked.length) {
    priceEl.textContent = `$${basePrice.toFixed(2)}`;
    return;
  }

  const additionsTotal = checked.reduce((sum, cb) => sum + Number(cb.dataset.modifierPrice), 0);
  const breakdown = checked
    .map((cb) => `${cb.dataset.modifierName.replace(/^Add /i, '')} $${Number(cb.dataset.modifierPrice).toFixed(2)}`)
    .join(', ');
  priceEl.textContent = `$${(basePrice + additionsTotal).toFixed(2)} ($${basePrice.toFixed(2)} + ${breakdown})`;
}

menuContainer.addEventListener('change', (event) => {
  if (event.target.matches('.item-modifiers input')) {
    const articleEl = event.target.closest('.item');
    if (articleEl) updateItemPriceDisplay(articleEl);
    const errorEl = event.target.closest('.item-modifiers')?.querySelector('.item-modifiers-error');
    if (errorEl) errorEl.hidden = true;
    return;
  }
  if (event.target.matches('.item-choice-group input')) {
    const errorEl = event.target.closest('.item-choice-group')?.querySelector('.item-choice-group-error');
    if (errorEl) errorEl.hidden = true;
  }
});

menuContainer.addEventListener('click', (event) => {
  const orderBtn = event.target.closest('.order-btn');
  if (orderBtn) {
    if (orderBtn.dataset.orderId) {
      markOrderDelivered(orderBtn);
    } else if (orderBtn.classList.contains('order-btn-in-cart')) {
      removeItemFromCart(orderBtn);
    } else {
      addItemToCart(orderBtn);
    }
    return;
  }
  if (event.target.closest('.staff-edit-link')) {
    return;
  }
  if (event.target.closest('.item-modifiers')) {
    return;
  }
  if (event.target.closest('.item-choice-groups')) {
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

// A floating "Your Order" button (bottom-left, opposite the Feedback tab)
// shown only once the pending cart has something in it — opens a modal to
// review, remove, and finally send everything as one notification to staff.
function ensureCartFab() {
  let btn = document.getElementById('cart-fab-btn');
  if (btn) return btn;
  btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'cart-fab-btn';
  btn.className = 'cart-fab-btn';
  btn.hidden = true;
  btn.addEventListener('click', openCartModal);
  document.body.appendChild(btn);
  return btn;
}

function updateCartBadge() {
  const cart = getPendingCart();
  const count = Object.keys(cart).length;
  const btn = ensureCartFab();
  if (count) {
    btn.textContent = `🛒 Your Order (${count}) — Review & Send`;
    btn.hidden = false;
  } else {
    btn.hidden = true;
  }
}

function ensureCartModal() {
  let modal = document.getElementById('cart-modal-overlay');
  if (modal) return modal;
  modal = document.createElement('div');
  modal.id = 'cart-modal-overlay';
  modal.className = 'item-modal-overlay';
  modal.hidden = true;
  modal.innerHTML = `
    <div class="item-modal cart-modal">
      <button type="button" class="item-modal-close" aria-label="Close">&times;</button>
      <h3 class="item-modal-name">Your Order</h3>
      <div id="cart-modal-body"></div>
    </div>
  `;
  document.body.appendChild(modal);
  modal.addEventListener('click', (event) => {
    if (event.target === modal) modal.hidden = true;
  });
  modal.querySelector('.item-modal-close').addEventListener('click', () => {
    modal.hidden = true;
  });
  return modal;
}

function renderCartModalBody() {
  const modal = ensureCartModal();
  const body = modal.querySelector('#cart-modal-body');
  const cart = getPendingCart();
  const itemNames = Object.keys(cart);

  if (!itemNames.length) {
    body.innerHTML = '<p class="hint">Your order is empty — tap "Add to Order" on anything you\'d like, from any menu page.</p>';
    return;
  }

  body.innerHTML = `
    <div class="cart-lines">
      ${itemNames
        .map((itemName) => {
          const entry = cart[itemName];
          const modifiersText = entry.modifiers && entry.modifiers.length ? entry.modifiers.join(', ') : '';
          return `
            <div class="cart-line" data-item-name="${escapeHtml(itemName)}">
              <div>
                <div class="cart-line-name">${escapeHtml(itemName)}</div>
                ${modifiersText ? `<div class="cart-line-modifiers hint">${escapeHtml(modifiersText)}</div>` : ''}
              </div>
              <button type="button" class="secondary cart-line-remove" aria-label="Remove ${escapeHtml(itemName)} from your order">&times;</button>
            </div>
          `;
        })
        .join('')}
    </div>
    <p class="hint">A staff member will come confirm your order — it hasn't been sent to the kitchen yet.</p>
    <button type="button" id="send-order-btn">Send Order</button>
    <p id="cart-status" class="status"></p>
  `;

  body.querySelectorAll('.cart-line-remove').forEach((removeBtn) => {
    removeBtn.addEventListener('click', () => {
      const itemName = removeBtn.closest('.cart-line').dataset.itemName;
      removePendingCartItem(itemName);
      const pageBtn = findOrderButtons(itemName).find((btn) => btn.classList.contains('order-btn-in-cart'));
      if (pageBtn) {
        removeItemFromCart(pageBtn);
      } else {
        updateCartBadge();
      }
      renderCartModalBody();
    });
  });

  body.querySelector('#send-order-btn').addEventListener('click', async () => {
    const sendBtn = body.querySelector('#send-order-btn');
    const statusEl = body.querySelector('#cart-status');
    sendBtn.disabled = true;
    statusEl.textContent = 'Sending...';
    statusEl.classList.remove('status-error', 'status-ok');

    const results = await sendPendingOrder();
    const failed = (results || []).filter((r) => !r.ok);

    if (!results || !results.length) {
      statusEl.textContent = "Couldn't send your order — check your connection and try again.";
      statusEl.classList.add('status-error');
      sendBtn.disabled = false;
      return;
    }

    if (failed.length) {
      statusEl.textContent = `${failed.length} item${failed.length === 1 ? '' : 's'} didn't go through — still in your order below, tap Send Order to retry.`;
      statusEl.classList.add('status-error');
      sendBtn.disabled = false;
      renderCartModalBody();
      return;
    }

    body.innerHTML = `
      <p class="status status-ok" style="font-size: 1rem;">
        Staff have been notified that you're ready to order — someone will be by shortly to confirm it.
      </p>
      <button type="button" id="cart-modal-done-btn">Got it</button>
    `;
    body.querySelector('#cart-modal-done-btn').addEventListener('click', () => {
      ensureCartModal().hidden = true;
    });
  });
}

function openCartModal() {
  renderCartModalBody();
  ensureCartModal().hidden = false;
}

async function revealStaffOnlyElementsIfLoggedIn() {
  const links = document.querySelectorAll('.staff-edit-link');
  const prices = document.querySelectorAll('.staff-revealable-price');
  const extras = document.querySelectorAll('.staff-revealable-extras');
  if (!links.length && !prices.length && !extras.length) return;
  try {
    const response = await fetch('/api/auth/me');
    if (response.ok) {
      staffLoggedIn = true;
      links.forEach((link) => { link.hidden = false; });
      prices.forEach((price) => { price.hidden = false; });
      extras.forEach((el) => { el.hidden = false; });
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
    revealStaffOnlyElementsIfLoggedIn();
  } catch (error) {
    menuContainer.innerHTML = `<p class="error">${escapeHtml(error.message)}</p>`;
  }
}

loadMenu();
