const toggle = document.querySelector('[data-sidebar-toggle]');
const sidebar = document.querySelector('[data-sidebar]');
toggle?.addEventListener('click', () => {
  const open = toggle.getAttribute('aria-expanded') !== 'true';
  toggle.setAttribute('aria-expanded', String(open));
  sidebar?.classList.toggle('hidden', !open);
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    sidebar?.classList.add('hidden');
    toggle?.setAttribute('aria-expanded', 'false');
    document.querySelectorAll('.admin-menu[open]').forEach(el => el.removeAttribute('open'));
  }
});
document.querySelectorAll('[data-confirm]').forEach(element => {
  element.addEventListener('click', event => {
    if (!window.confirm(element.dataset.confirm)) event.preventDefault();
  });
});
document.querySelector('[data-period]')?.addEventListener('change', event => {
  if (event.target.value === 'custom') return;
  const form = event.target.form;
  const end = new Date();
  end.setUTCDate(end.getUTCDate() - 1);
  const start = new Date(end);
  start.setUTCDate(start.getUTCDate() - Number(event.target.value) + 1);
  form.elements.start.value = start.toISOString().slice(0, 10);
  form.elements.end.value = end.toISOString().slice(0, 10);
});
document.querySelectorAll('form[method="get"]').forEach(form => {
  form.addEventListener('submit', () => {
    form.setAttribute('aria-busy', 'true');
    const button = form.querySelector('button[type="submit"],button:not([type])');
    if (button) { button.textContent = 'Loading…'; button.disabled = true; }
  });
});

document.querySelectorAll('[data-date-form] input[type="date"]').forEach(input => {
  input.addEventListener('change', () => { input.form.elements.days.value = 'custom'; });
});
