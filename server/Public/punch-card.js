// Shared visual punch card renderer — used by /rewards and /my-account.html
// so both show identical card art and dot-fill logic instead of drifting
// apart the way they did before this file existed (my-account.html kept
// the old plain-text pill design after /rewards moved to the card image).
function renderPunchCardInto(container, status) {
  const punches = status ? Math.min(status.punches, 10) : 0;
  const dots = Array.from(
    { length: 10 },
    (_, i) => `<span class="punch-dot ${i < punches ? 'punched' : ''}">${i < punches ? '&#10003;' : ''}</span>`
  ).join('');
  const rewardReady = Boolean(status && status.rewardReady);
  const bonusPoints = status ? status.bonusPoints : 0;

  container.innerHTML = `
    <div class="punch-card">
      <div class="punch-card-dots">${dots}</div>
    </div>
    ${
      rewardReady
        ? '<p class="punch-card-reward-ready"><span class="pill pill-approved">Free roll ready — show this to your server!</span></p>'
        : bonusPoints > 0
          ? `<p class="punch-card-reward-ready"><span class="pill">+${bonusPoints}/10 toward your next punch from shares</span></p>`
          : !status
            ? '<p class="hint" style="margin-top: 0.75rem;">No punches yet — order sushi to start earning!</p>'
            : ''
    }
  `;
}
