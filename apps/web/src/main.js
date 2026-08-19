import { createApp } from 'vue';
import App from './App.vue';
import { router } from './router.js';
import './styles.css';

function isDarkSurface(color) {
  const match = String(color).match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
  if (!match) return false;
  const luminance =
    (0.2126 * Number(match[1]) + 0.7152 * Number(match[2]) + 0.0722 * Number(match[3])) / 255;
  return luminance < 0.45;
}

function applyParentSurface() {
  try {
    if (window.parent === window) return;
    const parentDoc = window.parent.document;
    const sample =
      parentDoc.querySelector('.conversations-list-wrap') ||
      parentDoc.querySelector('.conversation-details-wrap');
    if (!sample || sample.getBoundingClientRect().height <= 0) return;
    const color = window.parent.getComputedStyle(sample).backgroundColor;
    if (!isDarkSurface(color)) return;
    document.documentElement.style.setProperty('--bg', color);
    document.documentElement.style.setProperty('--card', color);
    document.documentElement.style.setProperty('--surface', color);
    document.documentElement.style.background = color;
    document.body.style.background = color;
  } catch (error) {
    console.warn('nex-chamados: não foi possível copiar o fundo do Chatwoot', error);
  }
}

applyParentSurface();
createApp(App).use(router).mount('#app');
