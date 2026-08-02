function escapeHtmlSwag(str) {
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

let products = [];

async function loadProducts() {
  const listEl = document.getElementById('products-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/swag/products');
    if (!response.ok) throw new Error(`Unable to load products (${response.status}).`);
    products = await response.json();
    renderProductsList();
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlSwag(error.message)}</p>`;
  }
}

function syncProductsFromDOM() {
  const rows = document.querySelectorAll('#products-list tr[data-index]');
  rows.forEach((row) => {
    const i = Number(row.dataset.index);
    products[i].name = row.querySelector('.product-name-input').value.trim();
    products[i].price = Number(row.querySelector('.product-price-input').value) || 0;
    products[i].available = row.querySelector('.product-available-input').checked;
  });
}

function renderProductsList() {
  const listEl = document.getElementById('products-list');
  if (!products.length) {
    listEl.innerHTML = '<p class="hint">No products yet — add one below.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Name</th><th>Price</th><th>Available</th><th>Photos</th><th></th></tr></thead>
        <tbody>
          ${products
            .map(
              (p, i) => `
            <tr data-index="${i}">
              <td><input type="text" class="product-name-input" value="${escapeHtmlSwag(p.name)}" /></td>
              <td><input type="number" min="0" step="0.01" class="product-price-input" value="${p.price}" style="max-width: 7rem;" /></td>
              <td><input type="checkbox" class="product-available-input" ${p.available !== false ? 'checked' : ''} /></td>
              <td>
                <div class="item-thumb-gallery">
                  ${(p.images || [])
                    .map(
                      (url, photoIndex) => `
                    <div class="menu-photo-item">
                      <div class="item-thumb-wrap">
                        <a href="${escapeHtmlSwag(url)}" target="_blank" rel="noopener">
                          <img class="item-thumb" src="${escapeHtmlSwag(url)}" alt="${escapeHtmlSwag(p.name)}" />
                        </a>
                        <button type="button" class="thumb-remove-btn product-photo-remove-btn" data-photo-index="${photoIndex}" aria-label="Remove this photo">&times;</button>
                      </div>
                    </div>
                  `
                    )
                    .join('')}
                </div>
                <label class="photo-upload-btn">
                  + Add Photo
                  <input type="file" accept="image/*" class="product-photo-upload-input" hidden />
                </label>
                <p class="hint product-photo-status"></p>
              </td>
              <td><button type="button" class="secondary product-remove-btn">Remove</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;

  listEl.querySelectorAll('.product-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      syncProductsFromDOM();
      const index = Number(btn.closest('tr').dataset.index);
      products.splice(index, 1);
      renderProductsList();
    });
  });
  listEl.querySelectorAll('.product-photo-remove-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      syncProductsFromDOM();
      const productIndex = Number(btn.closest('tr').dataset.index);
      const photoIndex = Number(btn.dataset.photoIndex);
      products[productIndex].images.splice(photoIndex, 1);
      renderProductsList();
    });
  });
  listEl.querySelectorAll('.product-photo-upload-input').forEach((input) => {
    input.addEventListener('change', (event) => uploadProductPhoto(event, Number(input.closest('tr').dataset.index)));
  });
}

async function uploadProductPhoto(event, productIndex) {
  const file = event.target.files[0];
  if (!file) return;
  const statusEl = event.target.closest('td').querySelector('.product-photo-status');
  statusEl.textContent = 'Uploading...';
  statusEl.classList.remove('status-error');

  const formData = new FormData();
  formData.append('image', file);

  try {
    const response = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Upload failed (${response.status}).`);
    }
    const result = await response.json();
    syncProductsFromDOM();
    if (!products[productIndex].images) products[productIndex].images = [];
    products[productIndex].images.push(result.url);
    renderProductsList();
    setStatus(document.getElementById('products-status'), 'Photo added — click Save Products to keep it.', false);
  } catch (error) {
    statusEl.textContent = error.message;
    statusEl.classList.add('status-error');
  }
}

document.getElementById('products-form').addEventListener('submit', (event) => {
  event.preventDefault();
  syncProductsFromDOM();
  const nameInput = document.getElementById('new-product-name-input');
  const priceInput = document.getElementById('new-product-price-input');
  const name = nameInput.value.trim();
  const price = Number(priceInput.value);
  if (!name || !(price >= 0)) return;
  products.push({ id: crypto.randomUUID(), name, price, images: [], available: true });
  nameInput.value = '';
  priceInput.value = '';
  renderProductsList();
});

document.getElementById('save-products-btn').addEventListener('click', async () => {
  syncProductsFromDOM();
  const statusEl = document.getElementById('products-status');
  setStatus(statusEl, 'Saving...', false);
  try {
    const response = await staffFetch('/api/swag/products', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(products),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.reason || `Save failed (${response.status}).`);
    }
    products = await response.json();
    renderProductsList();
    setStatus(statusEl, 'Saved.', false);
  } catch (error) {
    setStatus(statusEl, error.message, true);
  }
});

document.getElementById('reload-products-btn').addEventListener('click', loadProducts);

// ---- Orders awaiting delivery ----

async function loadOrders() {
  const listEl = document.getElementById('orders-list');
  listEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/swag/orders');
    if (!response.ok) throw new Error(`Unable to load orders (${response.status}).`);
    const orders = await response.json();
    renderOrdersList(orders.filter((o) => o.status === 'paid'));
  } catch (error) {
    listEl.innerHTML = `<p class="status status-error">${escapeHtmlSwag(error.message)}</p>`;
  }
}

function renderOrdersList(orders) {
  const listEl = document.getElementById('orders-list');
  if (!orders.length) {
    listEl.innerHTML = '<p class="hint">Nothing waiting on delivery right now.</p>';
    return;
  }
  listEl.innerHTML = `
    <div class="data-table">
      <table>
        <thead><tr><th>Table</th><th>Items</th><th>Total</th><th>Paid</th><th></th></tr></thead>
        <tbody>
          ${orders
            .map(
              (o) => `
            <tr data-id="${escapeHtmlSwag(o.id)}">
              <td>${escapeHtmlSwag(o.tableId)}</td>
              <td>${o.items.map((it) => `${it.quantity}&times; ${escapeHtmlSwag(it.name)}`).join(', ')}</td>
              <td>$${o.totalAmount.toFixed(2)}</td>
              <td>${escapeHtmlSwag(o.paidAt || '')}</td>
              <td><button type="button" class="secondary order-deliver-btn">Mark Delivered</button></td>
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
    </div>
  `;
  listEl.querySelectorAll('.order-deliver-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = btn.closest('tr').dataset.id;
      btn.disabled = true;
      try {
        const response = await staffFetch(`/api/swag/orders/${encodeURIComponent(id)}/deliver`, { method: 'POST' });
        if (!response.ok) throw new Error(`Failed (${response.status}).`);
        loadOrders();
      } catch (error) {
        btn.disabled = false;
      }
    });
  });
}

document.getElementById('reload-orders-btn').addEventListener('click', loadOrders);

loadProducts();
loadOrders();
