const menuContainer = document.getElementById('menu');

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
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
          return `
            <article class="item">
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
        <section class="category">
          <h2>${escapeHtml(category.name)}</h2>
          ${noteMarkup}
          <div class="items">${itemMarkup}</div>
        </section>
      `;
    })
    .join('');
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
