const SECTIONS = [
  { key: 'menu', label: 'Food Menu' },
  { key: 'sushi', label: 'Sushi' },
  { key: 'drinks', label: 'Drinks' },
  { key: 'happy_hour', label: 'Happy Hour' },
];

const statusEl = document.getElementById('status');
const categoriesContainer = document.getElementById('categories');
const addCategoryBtn = document.getElementById('add-category-btn');
const addCategorySection = document.getElementById('add-category-section');
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
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}

function sectionLabel(key) {
  return SECTIONS.find((s) => s.key === key)?.label || key;
}

function categoryBlock(section, name, note, items) {
  const section_ = document.createElement('section');
  section_.className = 'edit-category';
  section_.dataset.section = section;

  section_.innerHTML = `
    <div class="edit-category-header">
      <input class="category-name" value="${escapeAttr(name)}" placeholder="Category name" />
      <button type="button" class="remove-category secondary">Remove category</button>
    </div>
    <input class="category-note-input" placeholder="Optional note (e.g. served with miso soup)" value="${escapeAttr(note)}" />
    <div class="edit-items"></div>
    <button type="button" class="add-item secondary">+ Add item</button>
  `;

  const itemsContainer = section_.querySelector('.edit-items');
  (items || []).forEach((item) => itemsContainer.appendChild(itemRow(item)));

  section_.querySelector('.add-item').addEventListener('click', () => {
    itemsContainer.appendChild(itemRow({ name: '', description: '', price: null, image: null }));
  });

  section_.querySelector('.remove-category').addEventListener('click', () => {
    if (confirm(`Remove the "${section_.querySelector('.category-name').value}" category?`)) {
      section_.remove();
    }
  });

  return section_;
}

function itemRow(item) {
  const row = document.createElement('div');
  row.className = 'edit-item';
  row.dataset.image = item.image || '';
  const priceValue = item.price != null ? Number(item.price).toFixed(2) : '';
  row.innerHTML = `
    <div class="edit-item-photo">
      <img class="item-thumb" src="${escapeAttr(item.image || '')}" ${item.image ? '' : 'hidden'} alt="" />
      <label class="photo-upload-btn secondary">
        Photo
        <input type="file" class="item-image-input" accept="image/png,image/jpeg,image/webp,image/gif" hidden />
      </label>
      <p class="photo-status status"></p>
    </div>
    <div class="edit-item-fields">
      <div class="edit-item-row-top">
        <input class="item-name" placeholder="Item name" value="${escapeAttr(item.name || '')}" />
        <input class="item-price" type="number" step="0.01" min="0" placeholder="No price" value="${priceValue}" />
        <button type="button" class="remove-item secondary" aria-label="Remove item">&times;</button>
      </div>
      <input class="item-desc" placeholder="Description" value="${escapeAttr(item.description || '')}" />
    </div>
  `;
  row.querySelector('.remove-item').addEventListener('click', () => row.remove());
  row.querySelector('.item-image-input').addEventListener('change', (event) => uploadItemImage(row, event));
  return row;
}

async function uploadItemImage(row, event) {
  const file = event.target.files[0];
  if (!file) return;
  const statusEl = row.querySelector('.photo-status');
  const thumb = row.querySelector('.item-thumb');
  setStatus(statusEl, 'Uploading...', false);

  const formData = new FormData();
  formData.append('image', file);

  try {
    const response = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!response.ok) {
      throw new Error(`Upload failed (${response.status}).`);
    }
    const result = await response.json();
    row.dataset.image = result.url;
    thumb.src = result.url;
    thumb.hidden = false;
    setStatus(statusEl, 'Photo added.', false);
  } catch (error) {
    setStatus(statusEl, error.message, true);
  }
}

function renderEditor(data) {
  restaurantName = data.restaurant || restaurantName;
  categoriesContainer.innerHTML = '';

  SECTIONS.forEach(({ key, label }) => {
    const cats = (data.categories || []).filter((c) => c.section === key);
    if (!cats.length) return;
    const heading = document.createElement('h3');
    heading.className = 'section-heading';
    heading.textContent = label;
    categoriesContainer.appendChild(heading);
    cats.forEach((category) => {
      categoriesContainer.appendChild(categoryBlock(key, category.name, category.note, category.items));
    });
  });
}

function collectMenuData() {
  const seenNames = new Set();
  const categories = [];
  const blocks = categoriesContainer.querySelectorAll('.edit-category');

  for (const block of blocks) {
    const section = block.dataset.section;
    const name = block.querySelector('.category-name').value.trim();
    if (!name) {
      throw new Error('Every category needs a name.');
    }
    const dedupeKey = `${section}::${name}`;
    if (seenNames.has(dedupeKey)) {
      throw new Error(`Category "${name}" is listed more than once in the same section.`);
    }
    seenNames.add(dedupeKey);

    const note = block.querySelector('.category-note-input').value.trim() || null;

    const items = [];
    const rows = block.querySelectorAll('.edit-item');
    for (const row of rows) {
      const itemName = row.querySelector('.item-name').value.trim();
      if (!itemName) continue;
      const description = row.querySelector('.item-desc').value.trim() || null;
      const priceRaw = row.querySelector('.item-price').value.trim();
      const price = priceRaw === '' ? null : Number.parseFloat(priceRaw);
      const image = row.dataset.image || null;
      items.push({ name: itemName, description, price, image });
    }

    categories.push({ section, name, note, items });
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
  const section = addCategorySection.value;
  categoriesContainer.appendChild(categoryBlock(section, 'New Category', '', []));
});

loadMenu().catch((error) => setStatus(statusEl, error.message, true));
