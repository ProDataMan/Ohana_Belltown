(function () {
  const overlay = document.createElement('div');
  overlay.className = 'lightbox-overlay';
  overlay.hidden = true;
  overlay.innerHTML = `
    <button type="button" class="lightbox-close" aria-label="Close">&times;</button>
    <img class="lightbox-image" src="" alt="" />
    <p class="lightbox-caption"></p>
  `;
  document.body.appendChild(overlay);

  const img = overlay.querySelector('.lightbox-image');
  const caption = overlay.querySelector('.lightbox-caption');

  function open(src, captionText) {
    img.src = src;
    caption.textContent = captionText || '';
    overlay.hidden = false;
  }

  function close() {
    overlay.hidden = true;
    img.src = '';
  }

  overlay.addEventListener('click', (event) => {
    if (event.target === overlay) close();
  });
  overlay.querySelector('.lightbox-close').addEventListener('click', close);
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close();
  });

  window.openLightbox = open;
})();
