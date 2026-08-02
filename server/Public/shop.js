function escapeHtml(str) {
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/// Same key/logic as menu-section.js's getTableId() — sharing the
/// sessionStorage key means a customer who already scanned their table's QR
/// code to browse the food menu doesn't need to scan anything again to shop.
function getTableId() {
  const fromQuery = new URLSearchParams(window.location.search).get('table');
  if (fromQuery) {
    sessionStorage.setItem('ohana_table_id', fromQuery);
    return fromQuery;
  }
  return sessionStorage.getItem('ohana_table_id');
}

function getCart() {
  try {
    return JSON.parse(sessionStorage.getItem('ohana_swag_cart') || '{}');
  } catch {
    return {};
  }
}

function setCart(cart) {
  sessionStorage.setItem('ohana_swag_cart', JSON.stringify(cart));
}

function clearCart() {
  sessionStorage.removeItem('ohana_swag_cart');
}

let products = [];
let checkoutAvailable = false;

async function loadShop() {
  const grid = document.getElementById('shop-grid');
  grid.innerHTML = '<p class="hint">Loading...</p>';

  const [productsRes, statusRes] = await Promise.all([
    fetch('/api/swag/products'),
    fetch('/api/swag/checkout-status'),
  ]);

  if (!productsRes.ok) {
    grid.innerHTML = '<p class="error">Couldn\'t load the shop right now — try again in a moment.</p>';
    return;
  }
  products = await productsRes.json();
  checkoutAvailable = statusRes.ok ? (await statusRes.json()).available : false;

  renderShopBanner();
  renderGrid();
  updateCartFab();

  document.getElementById('shop-no-table-hint').hidden = Boolean(getTableId());
}

function renderShopBanner() {
  const params = new URLSearchParams(window.location.search);
  const checkout = params.get('checkout');
  const banner = document.getElementById('shop-checkout-banner');
  if (checkout === 'success') {
    clearCart();
    banner.textContent = "Thanks! Your order is paid — a staff member will bring it to your table shortly.";
    banner.classList.add('status-ok');
    banner.hidden = false;
  } else if (checkout === 'cancelled') {
    banner.textContent = 'Checkout was cancelled — your cart is still here whenever you’re ready.';
    banner.classList.add('status-error');
    banner.hidden = false;
  }
}

function renderGrid() {
  const grid = document.getElementById('shop-grid');
  if (!products.length) {
    grid.innerHTML = '<p class="hint">Nothing in the shop yet — check back soon.</p>';
    return;
  }

  const cart = getCart();

  grid.innerHTML = products
    .map((product) => {
      const soldOut = product.available === false;
      const photo = (product.images || [])[0];
      const photoMarkup = photo
        ? `<img class="shop-card-photo" src="${escapeHtml(photo)}" alt="${escapeHtml(product.name)}" loading="lazy" />`
        : '<div class="shop-card-photo shop-card-photo-placeholder">No photo yet</div>';
      const qty = cart[product.id] || 0;

      return `
        <div class="shop-card${soldOut ? ' item-sold-out' : ''}" data-product-id="${escapeHtml(product.id)}">
          ${photoMarkup}
          <div class="shop-card-body">
            <h3>${escapeHtml(product.name)}</h3>
            <div class="price">$${product.price.toFixed(2)}</div>
            ${soldOut
              ? '<span class="sold-out-badge">Sold Out</span>'
              : `
                <div class="qty-stepper">
                  <button type="button" class="secondary qty-minus" aria-label="Decrease quantity">&minus;</button>
                  <span class="qty-value">${qty}</span>
                  <button type="button" class="secondary qty-plus" aria-label="Increase quantity">+</button>
                </div>
              `}
          </div>
        </div>
      `;
    })
    .join('');

  grid.querySelectorAll('.shop-card').forEach((card) => {
    const productId = card.dataset.productId;
    const minus = card.querySelector('.qty-minus');
    const plus = card.querySelector('.qty-plus');
    if (!minus || !plus) return;
    minus.addEventListener('click', () => changeQuantity(productId, -1));
    plus.addEventListener('click', () => changeQuantity(productId, 1));
  });
}

function changeQuantity(productId, delta) {
  const cart = getCart();
  const next = Math.max(0, (cart[productId] || 0) + delta);
  if (next === 0) {
    delete cart[productId];
  } else {
    cart[productId] = next;
  }
  setCart(cart);
  renderGrid();
  updateCartFab();
}

function updateCartFab() {
  const cart = getCart();
  const count = Object.values(cart).reduce((sum, n) => sum + n, 0);
  const btn = document.getElementById('shop-cart-fab-btn');
  if (!count) {
    btn.hidden = true;
    return;
  }
  btn.hidden = false;
  btn.textContent = `Cart (${count})`;
}

function ensureCartModal() {
  let modal = document.getElementById('shop-cart-modal-overlay');
  if (modal) return modal;
  modal = document.createElement('div');
  modal.id = 'shop-cart-modal-overlay';
  modal.className = 'item-modal-overlay';
  modal.hidden = true;
  modal.innerHTML = `
    <div class="item-modal cart-modal">
      <button type="button" class="item-modal-close" aria-label="Close">&times;</button>
      <h3 class="item-modal-name">Your Cart</h3>
      <div id="shop-cart-modal-body"></div>
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
  const body = modal.querySelector('#shop-cart-modal-body');
  const cart = getCart();
  const lines = Object.entries(cart)
    .map(([productId, quantity]) => ({ product: products.find((p) => p.id === productId), quantity }))
    .filter((line) => line.product);

  if (!lines.length) {
    body.innerHTML = '<p class="hint">Your cart is empty.</p>';
    return;
  }

  const total = lines.reduce((sum, line) => sum + line.product.price * line.quantity, 0);
  const tableId = getTableId();

  body.innerHTML = `
    <div class="cart-lines">
      ${lines
        .map(
          (line) => `
        <div class="cart-line" data-product-id="${escapeHtml(line.product.id)}">
          <div>
            <div class="cart-line-name">${escapeHtml(line.product.name)} &times; ${line.quantity}</div>
            <div class="cart-line-modifiers hint">$${(line.product.price * line.quantity).toFixed(2)}</div>
          </div>
          <button type="button" class="secondary cart-line-remove" aria-label="Remove ${escapeHtml(line.product.name)} from your cart">&times;</button>
        </div>
      `
        )
        .join('')}
    </div>
    <p style="font-weight: 700;">Total: $${total.toFixed(2)}</p>
    ${
      !checkoutAvailable
        ? '<p class="hint">Online checkout isn’t turned on yet — ask your server about picking these up at the register.</p>'
        : !tableId
        ? '<p class="hint">Scan the QR code on your table to check out — that’s how we know where to bring it.</p>'
        : `<button type="button" id="shop-checkout-btn">Checkout with Card &mdash; $${total.toFixed(2)}</button>
           <p id="shop-checkout-status" class="status"></p>`
    }
  `;

  body.querySelectorAll('.cart-line-remove').forEach((removeBtn) => {
    removeBtn.addEventListener('click', () => {
      const productId = removeBtn.closest('.cart-line').dataset.productId;
      const c = getCart();
      delete c[productId];
      setCart(c);
      renderGrid();
      updateCartFab();
      renderCartModalBody();
    });
  });

  const checkoutBtn = body.querySelector('#shop-checkout-btn');
  if (checkoutBtn) {
    checkoutBtn.addEventListener('click', async () => {
      const statusEl = body.querySelector('#shop-checkout-status');
      checkoutBtn.disabled = true;
      statusEl.textContent = 'Starting checkout...';
      statusEl.classList.remove('status-error');
      try {
        const response = await fetch('/api/swag/checkout', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            tableId,
            items: lines.map((line) => ({ productId: line.product.id, quantity: line.quantity })),
          }),
        });
        if (!response.ok) {
          const errBody = await response.json().catch(() => ({}));
          throw new Error(errBody.reason || `Checkout failed (${response.status}).`);
        }
        const result = await response.json();
        window.location.href = result.checkoutURL;
      } catch (error) {
        statusEl.textContent = error.message;
        statusEl.classList.add('status-error');
        checkoutBtn.disabled = false;
      }
    });
  }
}

document.getElementById('shop-cart-fab-btn').addEventListener('click', () => {
  renderCartModalBody();
  ensureCartModal().hidden = false;
});

loadShop();
