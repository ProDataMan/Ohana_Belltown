const REPO_OWNER = 'ProDataMan';
const REPO_NAME = 'Ohana_Belltown';
const REPO_BRANCH = 'main';
const FILE_PATH = 'docs/menu.json';
const API_BASE = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${FILE_PATH}`;

// Fine-grained token scoped to only this repo's Contents (read/write). Intentionally
// public: this page has no login, so anyone with the edit.html link can save changes.
const GITHUB_TOKEN = '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';

const tokenStatus = document.getElementById('token-status');
const editorPanel = document.getElementById('editor-panel');
const categoriesContainer = document.getElementById('categories');
const addCategoryBtn = document.getElementById('add-category-btn');
const reloadBtn = document.getElementById('reload-btn');
const saveBtn = document.getElementById('save-btn');
const saveStatus = document.getElementById('save-status');

let currentSha = null;

function setStatus(el, message, isError) {
  el.textContent = message;
  el.classList.toggle('status-error', Boolean(isError));
  el.classList.toggle('status-ok', !isError && Boolean(message));
}

function utf8ToBase64(str) {
  return btoa(unescape(encodeURIComponent(str)));
}

function base64ToUtf8(str) {
  return decodeURIComponent(escape(atob(str)));
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

function escapeAttr(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}

function renderEditor(data) {
  categoriesContainer.innerHTML = '';
  const categories = Object.entries(data.categories || {});
  categories.forEach(([name, items]) => {
    categoriesContainer.appendChild(categoryBlock(name, items));
  });
}

function collectMenuData() {
  const categories = {};
  const blocks = categoriesContainer.querySelectorAll('.edit-category');

  for (const block of blocks) {
    const name = block.querySelector('.category-name').value.trim();
    if (!name) {
      throw new Error('Every category needs a name.');
    }
    if (categories[name]) {
      throw new Error(`Category "${name}" is listed more than once.`);
    }

    const items = [];
    const rows = block.querySelectorAll('.edit-item');
    for (const row of rows) {
      const itemName = row.querySelector('.item-name').value.trim();
      if (!itemName) continue;
      const description = row.querySelector('.item-desc').value.trim();
      const price = Number.parseFloat(row.querySelector('.item-price').value) || 0;
      items.push({ name: itemName, description, price });
    }

    categories[name] = items;
  }

  return {
    restaurant: 'Ohana Belltown',
    lastUpdated: new Date().toISOString().slice(0, 10),
    categories,
  };
}

async function githubRequest(method, body) {
  const response = await fetch(API_BASE + (method === 'GET' ? `?ref=${REPO_BRANCH}` : ''), {
    method,
    headers: {
      Authorization: `Bearer ${GITHUB_TOKEN}`,
      Accept: 'application/vnd.github+json',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const detail = await response.json().catch(() => ({}));
    throw new Error(detail.message || `GitHub request failed (${response.status}).`);
  }

  return response.json();
}

async function loadMenu() {
  setStatus(tokenStatus, 'Loading current menu...', false);
  const file = await githubRequest('GET');
  currentSha = file.sha;
  const data = JSON.parse(base64ToUtf8(file.content));
  renderEditor(data);
  setStatus(tokenStatus, '', false);
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
    const content = JSON.stringify(data, null, 2) + '\n';
    const result = await githubRequest('PUT', {
      message: `Update menu via editor (${data.lastUpdated})`,
      content: utf8ToBase64(content),
      sha: currentSha,
      branch: REPO_BRANCH,
    });
    currentSha = result.content.sha;
    setStatus(saveStatus, 'Saved! The live site will update in a minute or two.', false);
  } catch (error) {
    if (/sha/i.test(error.message)) {
      setStatus(saveStatus, 'Someone else updated the menu. Click "Reload latest" and re-apply your changes.', true);
    } else {
      setStatus(saveStatus, error.message, true);
    }
  } finally {
    saveBtn.disabled = false;
  }
}

reloadBtn.addEventListener('click', () => loadMenu().catch((error) => setStatus(tokenStatus, error.message, true)));
saveBtn.addEventListener('click', saveMenu);
addCategoryBtn.addEventListener('click', () => {
  categoriesContainer.appendChild(categoryBlock('New Category', []));
});

loadMenu().catch((error) => setStatus(tokenStatus, error.message, true));
