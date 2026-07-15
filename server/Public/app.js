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
  const categories = data.categories || [];

  if (!categories.length) {
    menuContainer.innerHTML = '<p class="error">No menu categories were found.</p>';
    return;
  }

  menuContainer.innerHTML = categories
    .map((category) => {
      const itemMarkup = (category.items || [])
        .map((item) => {
          const price = Number(item.price || 0).toFixed(2);
          return `
            <article class="item">
              <div>
                <h3>${escapeHtml(item.name)}</h3>
                <p>${escapeHtml(item.description || '')}</p>
              </div>
              <div class="price">$${price}</div>
            </article>
          `;
        })
        .join('');

      return `
        <section class="category">
          <h2>${escapeHtml(category.name)}</h2>
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
