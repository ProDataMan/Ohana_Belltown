function escapeHtmlUsers(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

const usersListEl = document.getElementById('users-list');

async function loadUsers() {
  usersListEl.innerHTML = '<p class="hint">Loading...</p>';
  try {
    const response = await staffFetch('/api/users');
    if (!response.ok) throw new Error(`Unable to load users (${response.status}).`);
    const users = await response.json();
    usersListEl.innerHTML = `
      <div class="data-table">
        <table>
          <thead>
            <tr><th>Name</th><th>Username</th><th>Role</th><th></th><th></th></tr>
          </thead>
          <tbody>
            ${users
              .map(
                (u) => `
              <tr data-id="${u.id}">
                <td>${escapeHtmlUsers(u.displayName)}${u.mustChangePassword ? ' <span class="pill">must change password</span>' : ''}</td>
                <td>@${escapeHtmlUsers(u.username)}</td>
                <td>
                  <select class="role-select">
                    <option value="employee" ${u.role === 'employee' ? 'selected' : ''}>Employee</option>
                    <option value="admin" ${u.role === 'admin' ? 'selected' : ''}>Admin</option>
                  </select>
                </td>
                <td><button type="button" class="secondary save-role-btn">Save role</button></td>
                <td><button type="button" class="secondary reset-password-btn">Reset password</button></td>
              </tr>
            `
              )
              .join('')}
          </tbody>
        </table>
      </div>
    `;
    usersListEl.querySelectorAll('.save-role-btn').forEach((btn) =>
      btn.addEventListener('click', (e) => saveRole(e.target.closest('tr')))
    );
    usersListEl.querySelectorAll('.reset-password-btn').forEach((btn) =>
      btn.addEventListener('click', (e) => resetPassword(e.target.closest('tr')))
    );
  } catch (error) {
    usersListEl.innerHTML = `<p class="status status-error">${escapeHtmlUsers(error.message)}</p>`;
  }
}

async function saveRole(row) {
  const id = row.dataset.id;
  const role = row.querySelector('.role-select').value;
  try {
    const response = await staffFetch(`/api/users/${id}/role`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role }),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    await loadUsers();
  } catch (error) {
    usersListEl.insertAdjacentHTML('afterbegin', `<p class="status status-error">${escapeHtmlUsers(error.message)}</p>`);
  }
}

async function resetPassword(row) {
  const id = row.dataset.id;
  const newPassword = window.prompt('Enter a new temporary password for this user:');
  if (!newPassword) return;
  try {
    const response = await staffFetch(`/api/users/${id}/reset-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ newPassword }),
    });
    if (!response.ok) throw new Error(`Failed (${response.status}).`);
    await loadUsers();
  } catch (error) {
    usersListEl.insertAdjacentHTML('afterbegin', `<p class="status status-error">${escapeHtmlUsers(error.message)}</p>`);
  }
}

document.getElementById('reload-btn').addEventListener('click', loadUsers);

loadUsers();
