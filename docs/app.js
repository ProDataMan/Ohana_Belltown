const menuContainer = document.getElementById('menu');
const menuUrl = new URL('./menu.json', window.location.href);

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderMenu(data) {
  const categories = Object.entries(data.categories || {});

  if (!categories.length) {
    menuContainer.innerHTML = '<p class="error">No menu categories were found.</p>';
    return;
  }

  menuContainer.innerHTML = categories
    .map(([category, items]) => {
      const itemMarkup = (items || [])
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
          <h2>${escapeHtml(category)}</h2>
          <div class="items">${itemMarkup}</div>
        </section>
      `;
    })
    .join('');
}

async function loadMenu() {
  try {
    const response = await fetch(menuUrl);
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
