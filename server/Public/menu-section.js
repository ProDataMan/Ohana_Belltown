const menuContainer = document.getElementById('menu');

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

  menuContainer.innerHTML = categories
    .map((category) => {
      const noteMarkup = category.note ? `<p class="category-note">${escapeHtml(category.note)}</p>` : '';
      const itemMarkup = (category.items || [])
        .map((item) => {
          const priceMarkup = item.price != null ? `<div class="price">$${Number(item.price).toFixed(2)}</div>` : '';
          const imageMarkup = item.image
            ? `<img class="item-photo" src="${escapeHtml(item.image)}" alt="${escapeHtml(item.name)}" loading="lazy" />`
            : '';
          const searchText = `${item.name} ${item.description || ''}`.toLowerCase();
          return `
            <article class="item" data-search="${escapeHtml(searchText)}">
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
