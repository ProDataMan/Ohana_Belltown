const statusEl = document.getElementById('status');
const categoriesContainer = document.getElementById('categories');
const addCategoryBtn = document.getElementById('add-category-btn');
const reloadBtn = document.getElementById('reload-btn');
const saveBtn = document.getElementById('save-btn');
const saveStatus = document.getElementById('save-status');

let restaurantName = 'Ohana Belltown';

function setStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

function escapeAttr(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}

function categoryBlock(name, items) {
  const section = document.createElement('section');
  section.className = 'edit-category';

  section.innerHTML = `
    <div class="edit-category-header">
      <input class="category-name" value="${escapeAttr(name)}" placeholder="Category name" />
      <button type="button" class="remove-category secondary">Remove category</button>
    </div>
    <div class="edit-items"></div>
    <button type="button" class="add-item secondary">+ Add item</button>
  `;

  const itemsContainer = section.querySelector('.edit-items');
  (items || []).forEach((item) => itemsContainer.appendChild(itemRow(item)));

  section.querySelector('.add-item').addEventListener('click', () => {
    itemsContainer.appendChild(itemRow({ name: '', description: '', price: 0 }));
  });

  section.querySelector('.remove-category').addEventListener('click', () => {
    if (confirm(`Remove the "${section.querySelector('.category-name').value}" category?`)) {
      section.remove();
    }
  });

  return section;
}

function itemRow(item) {
  const row = document.createElement('div');
  row.className = 'edit-item';
  row.innerHTML = `
    <input class="item-name" placeholder="Item name" value="${escapeAttr(item.name || '')}" />
    <input class="item-desc" placeholder="Description" value="${escapeAttr(item.description || '')}" />
    <input class="item-price" type="number" step="0.01" min="0" value="${Number(item.price || 0).toFixed(2)}" />
    <button type="button" class="remove-item secondary" aria-label="Remove item">&times;</button>
  `;
  row.querySelector('.remove-item').addEventListener('click', () => row.remove());
  return row;
}

function renderEditor(data) {
  restaurantName = data.restaurant || restaurantName;
  categoriesContainer.innerHTML = '';
  (data.categories || []).forEach((category) => {
    categoriesContainer.appendChild(categoryBlock(category.name, category.items));
  });
}

function collectMenuData() {
  const seenNames = new Set();
  const categories = [];
  const blocks = categoriesContainer.querySelectorAll('.edit-category');

  for (const block of blocks) {
    const name = block.querySelector('.category-name').value.trim();
    if (!name) {
      throw new Error('Every category needs a name.');
    }
    if (seenNames.has(name)) {
      throw new Error(`Category "${name}" is listed more than once.`);
    }
    seenNames.add(name);

    const items = [];
    const rows = block.querySelectorAll('.edit-item');
    for (const row of rows) {
      const itemName = row.querySelector('.item-name').value.trim();
      if (!itemName) continue;
      const description = row.querySelector('.item-desc').value.trim();
      const price = Number.parseFloat(row.querySelector('.item-price').value) || 0;
      items.push({ name: itemName, description, price });
    }

    categories.push({ name, items });
  }

  return {
    restaurant: restaurantName,
    lastUpdated: new Date().toISOString().slice(0, 10),
    categories,
  };
}

async function loadMenu() {
  setStatus(statusEl, 'Loading current menu...', false);
  const response = await fetch('/api/menu');
  if (!response.ok) {
    throw new Error(`Unable to load the menu (${response.status}).`);
  }
  const data = await response.json();
  renderEditor(data);
  setStatus(statusEl, '', false);
}

async function saveMenu() {
  let data;
  try {
    data = collectMenuData();
  } catch (error) {
    setStatus(saveStatus, error.message, true);
    return;
  }

  saveBtn.disabled = true;
  setStatus(saveStatus, 'Saving...', false);

  try {
    const response = await fetch('/api/menu', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!response.ok) {
      throw new Error(`Save failed (${response.status}).`);
    }
    setStatus(saveStatus, 'Saved! The live site is already up to date.', false);
  } catch (error) {
    setStatus(saveStatus, error.message, true);
  } finally {
    saveBtn.disabled = false;
  }
}

reloadBtn.addEventListener('click', () => loadMenu().catch((error) => setStatus(statusEl, error.message, true)));
saveBtn.addEventListener('click', saveMenu);
addCategoryBtn.addEventListener('click', () => {
  categoriesContainer.appendChild(categoryBlock('New Category', []));
});

loadMenu().catch((error) => setStatus(statusEl, error.message, true));
