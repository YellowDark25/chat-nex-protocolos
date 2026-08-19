<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { api } from './api.js';
import { isEmbedded } from './embed.js';

const route = useRoute();
const embedded = isEmbedded();
const accountId = computed(() => api.accountId());
const inboxUrl = computed(() =>
  accountId.value ? `/app/accounts/${accountId.value}/dashboard` : '/app'
);
const fillsViewport = computed(() => route.name === 'lista' || route.name === 'dossie');
</script>

<template>
  <div class="shell" :class="{ embedded, 'shell-fill': fillsViewport }">
    <aside v-if="!embedded" class="nav">
      <a :href="inboxUrl">Conversas</a>
      <router-link to="/" class="active">Chamados</router-link>
    </aside>
    <main class="main" :class="{ 'main-fill': fillsViewport }">
      <router-view />
    </main>
  </div>
</template>
