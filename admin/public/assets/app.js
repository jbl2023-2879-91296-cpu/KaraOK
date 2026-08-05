const toggle = document.querySelector('[data-sidebar-toggle]');
const sidebar = document.querySelector('[data-sidebar]');
toggle?.addEventListener('click', () => sidebar?.classList.toggle('hidden'));

document.querySelectorAll('[data-confirm]').forEach((element) => {
  element.addEventListener('click', (event) => {
    if (!window.confirm(element.dataset.confirm)) event.preventDefault();
  });
});
