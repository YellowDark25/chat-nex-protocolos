<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';

const MENU_GAP = 6;
const MENU_MAX_HEIGHT = 280;
const OPTION_HEIGHT = 36;
const MENU_PADDING = 12;

const props = defineProps({
  modelValue: { type: [String, Number, Array], default: '' },
  options: { type: Array, required: true },
  placeholder: { type: String, default: 'Selecionar' },
  compact: { type: Boolean, default: false },
  multiple: { type: Boolean, default: false }
});

const emit = defineEmits(['update:modelValue']);

const isOpen = ref(false);
const rootRef = ref(null);
const menuRef = ref(null);
const menuStyle = ref({});

const selectedValues = computed(() =>
  props.multiple ? (Array.isArray(props.modelValue) ? props.modelValue.map(String) : []) : []
);
const selectedOption = computed(() =>
  props.options.find((option) => String(option.value) === String(props.modelValue))
);
const selectedLabel = computed(() => {
  if (!props.multiple) return selectedOption.value?.label || props.placeholder;
  if (!selectedValues.value.length) return props.placeholder;
  const labels = props.options
    .filter((option) => selectedValues.value.includes(String(option.value)))
    .map((option) => option.label);
  if (labels.length === props.options.length) return 'Todos';
  return labels.join(', ');
});

function isSelected(option) {
  if (props.multiple) return selectedValues.value.includes(String(option.value));
  return String(option.value) === String(props.modelValue);
}

function toggle() {
  isOpen.value = !isOpen.value;
}

function selectOption(option) {
  if (!props.multiple) {
    emit('update:modelValue', option.value);
    isOpen.value = false;
    return;
  }
  const current = Array.isArray(props.modelValue) ? [...props.modelValue] : [];
  const index = current.findIndex((value) => String(value) === String(option.value));
  if (index >= 0) current.splice(index, 1);
  else current.push(option.value);
  emit('update:modelValue', current);
}

function estimatedMenuHeight() {
  return Math.min(props.options.length * OPTION_HEIGHT + MENU_PADDING, MENU_MAX_HEIGHT);
}

function placeMenu() {
  const trigger = rootRef.value?.querySelector('.nex-select-trigger');
  if (!trigger) return;

  const rect = trigger.getBoundingClientRect();
  const spaceBelow = window.innerHeight - rect.bottom;
  const openUpward = spaceBelow < estimatedMenuHeight() + MENU_GAP;

  menuStyle.value = {
    position: 'fixed',
    left: `${rect.left}px`,
    minWidth: `${Math.max(rect.width, 72)}px`,
    zIndex: 80,
    ...(openUpward
      ? { bottom: `${window.innerHeight - rect.top + MENU_GAP}px`, top: 'auto' }
      : { top: `${rect.bottom + MENU_GAP}px`, bottom: 'auto' })
  };
}

function onDocumentPointerDown(event) {
  const target = event.target;
  if (rootRef.value?.contains(target) || menuRef.value?.contains(target)) return;
  isOpen.value = false;
}

function onEscape(event) {
  if (event.key === 'Escape') isOpen.value = false;
}

function bindMenuListeners() {
  document.addEventListener('pointerdown', onDocumentPointerDown);
  document.addEventListener('keydown', onEscape);
  window.addEventListener('resize', placeMenu);
  window.addEventListener('scroll', placeMenu, true);
}

function unbindMenuListeners() {
  document.removeEventListener('pointerdown', onDocumentPointerDown);
  document.removeEventListener('keydown', onEscape);
  window.removeEventListener('resize', placeMenu);
  window.removeEventListener('scroll', placeMenu, true);
}

watch(isOpen, async (open) => {
  if (open) {
    bindMenuListeners();
    await nextTick();
    placeMenu();
    return;
  }
  unbindMenuListeners();
});

onBeforeUnmount(unbindMenuListeners);
</script>

<template>
  <div ref="rootRef" class="nex-select" :class="{ open: isOpen, compact }">
    <button
      class="nex-select-trigger"
      type="button"
      :aria-expanded="isOpen"
      aria-haspopup="listbox"
      @click="toggle"
    >
      <span class="nex-select-label">{{ selectedLabel }}</span>
      <span class="nex-select-divider" aria-hidden="true" />
      <span class="nex-select-caret" aria-hidden="true">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="m6 9 6 6 6-6" />
        </svg>
      </span>
    </button>
    <Teleport to="body">
      <ul
        v-if="isOpen"
        ref="menuRef"
        class="nex-select-menu"
        role="listbox"
        :aria-multiselectable="multiple || undefined"
        :style="menuStyle"
      >
        <li v-for="option in options" :key="`${option.value}-${option.label}`">
          <button
            class="nex-select-option"
            :class="{ selected: isSelected(option) }"
            type="button"
            role="option"
            :aria-selected="isSelected(option)"
            @click="selectOption(option)"
          >
            <span>{{ option.label }}</span>
            <svg
              v-if="isSelected(option)"
              class="nex-select-check"
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              aria-hidden="true"
            >
              <path d="M20 6 9 17l-5-5" />
            </svg>
          </button>
        </li>
      </ul>
    </Teleport>
  </div>
</template>
