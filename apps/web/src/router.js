import { createRouter, createWebHistory } from 'vue-router';
import Lista from './views/Lista.vue';
import Dossie from './views/Dossie.vue';
import Novo from './views/Novo.vue';

export const router = createRouter({
  history: createWebHistory('/chamados/'),
  routes: [
    { path: '/', name: 'lista', component: Lista },
    { path: '/novo', name: 'novo', component: Novo },
    { path: '/:number', name: 'dossie', component: Dossie, props: true }
  ]
});
