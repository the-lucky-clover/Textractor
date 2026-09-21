import { listen } from '@tauri-apps/api/event';
import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-opener';
import { getCurrentWindow } from '@tauri-apps/api/window';

// State
let currentSettings = {};
let historyRecords = [];
let activeToastId = null;

// === DOM Elements ===
const app = document.getElementById('app');
const loadingScreen = document.getElementById('loading');
const mainWindow = document.getElementById('main-window');
const fabCapture = document.getElementById('fab-capture');
const captureOverlay = document.getElementById('capture-overlay');
const toastContainer = document.getElementById('toast-container');

// === Settings Bindings ===
document.addEventListener('DOMContentLoaded', () => {
  initializeApp();
  setupEventListeners();
  loadSettings();
  loadHistory();
});

async function initializeApp() {
  try {
    // Load settings
    currentSettings = await invoke('get_settings');
    applySettings();
    
    // Hide loading screen, show main window
    loadingScreen.classList.add('fade-out');
    setTimeout(() => {
      loadingScreen.classList.add('hidden');
      mainWindow.classList.remove('hidden');
      setTimeout(() => mainWindow.classList.add('visible'), 50);
    }, 500);
    
    listenToasts();
  } catch (err) {
    console.error('Failed to initialize:', err);
    showToast('Failed to start', err.message, 'error');
  }
}

function setupEventListeners() {
  // Navigation
  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tab = item.dataset.tab;
      switchTab(tab);
    });
  });
  
  // FAB capture
  fabCapture.addEventListener('click', () => {
    invoke('trigger_capture');
  });
  
  // Keyboard shortcut Ctrl+Shift+2
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.shiftKey && e.key === '2') {
      e.preventDefault();
      invoke('trigger_capture');
    }
  });
  
  // Toggle switches
  setupToggle('toggle-paste-plain', 'paste_as_plain_text');
  setupToggle('toggle-flatten', 'flatten_text');
  setupToggle('toggle-tables', 'window_capture_as_table');
  setupToggle('toggle-pii', 'pii_redaction_enabled');
  setupToggle('toggle-clipboard-ocr', 'clipboard_image_ocr');
  setupToggle('toggle-confidence', 'show_confidence_badge');
  setupToggle('toggle-menubar-color', 'menubar_color_icon');
  setupToggle('toggle-reduce-motion', 'reduce_motion');
  
  // Slider
  const weirdnessSlider = document.getElementById('weirdness-slider');
  const weirdnessValue = document.getElementById('weirdness-value');
  weirdnessSlider.addEventListener('input', (e) => {
    const val = e.target.value;
    weirdnessValue.textContent = `${val}%`;
    currentSettings.weirdness = parseInt(val) / 100;
    debounceSaveSettings();
  });
  
  // History limit
  const historyLimit = document.getElementById('history-limit');
  historyLimit.addEventListener('change', (e) => {
    currentSettings.history_entry_limit = parseInt(e.target.value);
    saveSettings();
  });
  
  // OCR language
  const ocrLanguage = document.getElementById('ocr-language');
  ocrLanguage.addEventListener('change', (e) => {
    currentSettings.ui_language = e.target.value;
    saveSettings();
  });
  
  // Search
  const searchInput = document.getElementById('search-input');
  searchInput.addEventListener('input', debounce((e) => {
    filterHistory(e.target.value);
  }, 300));
  
  // Export button
  document.getElementById('export-btn').addEventListener('click', exportHistory);
  
  // Clear history
  document.getElementById('clear-history-btn').addEventListener('click', async () => {
    if (confirm('Clear all history?')) {
      await invoke('clear_history');
      await loadHistory();
    }
  });
  
  // Window controls
  document.getElementById('minimize-btn').addEventListener('click', () => {
    getCurrentWindow().minimize();
  });
  
  document.getElementById('maximize-btn').addEventListener('click', async () => {
    const window = getCurrentWindow();
    if (await window.isMaximized()) {
      await window.unmaximize();
    } else {
      await window.maximize();
    }
  });
  
  document.getElementById('close-btn').addEventListener('click', () => {
    getCurrentWindow().close();
  });
}

function setupToggle(id, settingKey) {
  const toggle = document.getElementById(id);
  if (!toggle) return;
  
  // Sync with settings
  if (currentSettings[settingKey]) {
    toggle.classList.add('active');
  }
  
  toggle.addEventListener('click', () => {
    toggle.classList.toggle('active');
    currentSettings[settingKey] = toggle.classList.contains('active');
    saveSettings();
  });
}

function applySettings() {
  const settings = currentSettings;
  
  // Apply toggles
  if (settings.paste_as_plain_text) {
    document.getElementById('toggle-paste-plain')?.classList.add('active');
  }
  if (settings.flatten_text) {
    document.getElementById('toggle-flatten')?.classList.add('active');
  }
  if (settings.window_capture_as_table) {
    document.getElementById('toggle-tables')?.classList.add('active');
  }
  if (settings.pii_redaction_enabled) {
    document.getElementById('toggle-pii')?.classList.add('active');
  }
  if (settings.show_confidence_badge) {
    document.getElementById('toggle-confidence')?.classList.add('active');
  }
  if (settings.clipboard_image_ocr) {
    document.getElementById('toggle-clipboard-ocr')?.classList.add('active');
  }
  if (settings.menubar_color_icon) {
    document.getElementById('toggle-menubar-color')?.classList.add('active');
  }
  if (settings.reduce_motion) {
    document.getElementById('toggle-reduce-motion')?.classList.add('active');
  }
  
  // Weirdness slider
  const weirdnessSlider = document.getElementById('weirdness-slider');
  const weirdnessValue = document.getElementById('weirdness-value');
  if (weirdnessSlider && weirdnessValue) {
    weirdnessSlider.value = Math.round(settings.weirdness * 100);
    weirdnessValue.textContent = `${Math.round(settings.weirdness * 100)}%`;
  }
  
  // History limit
  const historyLimit = document.getElementById('history-limit');
  if (historyLimit) {
    historyLimit.value = settings.history_entry_limit || 200;
  }
  
  // OCR language
  const ocrLanguage = document.getElementById('ocr-language');
  if (ocrLanguage && settings.ui_language) {
    ocrLanguage.value = settings.ui_language;
  }
}

// === Settings ===
let saveTimeout = null;
function debounceSaveSettings() {
  clearTimeout(saveTimeout);
  saveTimeout = setTimeout(saveSettings, 300);
}

async function saveSettings() {
  try {
    await invoke('update_settings', { settings: currentSettings });
    if (currentSettings.clipboard_image_ocr) {
      // Clipboard OCR enabled - toast notification
      showToast('Clipboard OCR Enabled', 'Monitoring clipboard for images...', 'success', 3000);
    }
  } catch (err) {
    showToast('Error', `Failed to save settings: ${err.message}`, 'error');
  }
}

async function loadSettings() {
  try {
    currentSettings = await invoke('get_settings');
    applySettings();
  } catch (err) {
    console.error('Failed to load settings:', err);
  }
}

// === History ===
async function loadHistory() {
  try {
    historyRecords = await invoke('get_history');
    renderHistory(historyRecords);
  } catch (err) {
    console.error('Failed to load history:', err);
  }
}

function renderHistory(records) {
  const historyList = document.getElementById('history-list');
  if (!historyList) return;
  
  if (records.length === 0) {
    historyList.innerHTML = `
      <div class="empty-history">
        <i class="fas fa-clipboard-list"></i>
        <h3>No captures yet</h3>
        <p>Captured text will appear here.</p>
      </div>
    `;
    return;
  }
  
  historyList.innerHTML = records.map(record => `
    <div class="history-item" data-id="${record.id}">
      <div class="history-item-preview">
        <i class="fas fa-${getModeIcon(record.mode)}"></i>
      </div>
      <div class="history-item-content">
        <div class="history-item-header">
          <span class="history-item-mode">${record.mode}</span>
          <span class="history-item-time">${formatTimestamp(record.timestamp)}</span>
        </div>
        <div class="history-item-text">${escapeHtml(record.text)}</div>
        <div class="history-meta">
          <span><i class="fas fa-chart-bar"></i> ${(record.confidence * 100).toFixed(0)}%</span>
          ${currentSettings.show_confidence_badge ? 
            `<span class="confidence-badge confidence-${getConfidenceLevel(record.confidence)}">${getConfidenceLabel(record.confidence)}</span>` : ''}
          <span><i class="fas fa-clock"></i> ${record.processing_time_ms}ms</span>
        </div>
        <div class="history-item-actions">
          <button class="btn btn-secondary" onclick="copyText('${escapeHtml(record.text)}')">
            <i class="fas fa-copy"></i> Copy
          </button>
          <button class="btn btn-danger" onclick="deleteCapture('${record.id}')">
            <i class="fas fa-trash"></i> Delete
          </button>
        </div>
      </div>
    </div>
  `).join('');
}

function getModeIcon(mode) {
  switch (mode) {
    case 'clipboard': return 'copy';
    case 'region': return 'crosshairs';
    case 'window': return 'window-maximize';
    case 'fullscreen': return 'expand';
    default: return 'qrcode';
  }
}

function getConfidenceLevel(confidence) {
  if (confidence >= 0.85) return 'excellent';
  if (confidence >= 0.70) return 'good';
  if (confidence >= 0.50) return 'fair';
  return 'poor';
}

function getConfidenceLabel(confidence) {
  if (confidence >= 0.85) return 'Excellent';
  if (confidence >= 0.70) return 'Good';
  if (confidence >= 0.50) return 'Fair';
  return 'Poor';
}

function formatTimestamp(timestamp) {
  try {
    const date = new Date(timestamp);
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch {
    return timestamp;
  }
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function filterHistory(query) {
  try {
    const results = query.length > 0 ? await invoke('search_history', { query }) : historyRecords;
    renderHistory(results);
  } catch (err) {
    console.error('Search failed:', err);
  }
}

async function deleteCapture(id) {
  try {
    await invoke('delete_capture', { id });
    await loadHistory();
    showToast('Deleted', 'Capture removed from history.', 'info', 2000);
  } catch (err) {
    showToast('Error', `Failed to delete: ${err.message}`, 'error');
  }
}

async function exportHistory() {
  try {
    const format = prompt('Export format: json, csv, or markdown');
    if (!format) return;
    
    const result = await invoke('export_history', { format: format.toLowerCase() });
    
    // Download the file
    const blob = new Blob([result], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Textractor-export.${format.toLowerCase()}`;
    a.click();
    URL.revokeObjectURL(url);
    
    showToast('Exported', `History exported as ${format}.`, 'success', 3000);
  } catch (err) {
    showToast('Error', `Export failed: ${err.message}`, 'error');
  }
}

async function copyText(text) {
  try {
    await invoke('copy_text', { text });
    showToast('Copied', 'Text copied to clipboard.', 'success', 2000);
  } catch (err) {
    showToast('Error', `Copy failed: ${err.message}`, 'error');
  }
}

// === Tabs ===
function switchTab(tabName) {
  document.querySelectorAll('.nav-item').forEach(item => {
    item.classList.toggle('active', item.dataset.tab === tabName);
  });
  
  document.querySelectorAll('.tab-content').forEach(tab => {
    tab.classList.toggle('active', tab.id === `tab-${tabName}`);
  });
}

// === Toasts ===
function showToast(title, body, kind = 'info', duration = 4000) {
  const id = Date.now().toString();
  const toast = document.createElement('div');
  toast.className = `toast ${kind}`;
  toast.style.setProperty('--duration', `${duration}ms`);
  toast.id = id;
  toast.innerHTML = `
    <div class="toast-content">
      <div class="toast-header">
        <span class="toast-title">${escapeHtml(title)}</span>
        <button class="toast-close" onclick="dismissToast('${id}')">×</button>
      </div>
      <div class="toast-body">${escapeHtml(body)}</div>
    </div>
  `;
  
  toastContainer.appendChild(toast);
  
  // Auto-remove
  setTimeout(() => dismissToast(id), duration);
}

function dismissToast(id) {
  const toast = document.getElementById(id);
  if (toast) {
    toast.classList.add('hidden');
    setTimeout(() => toast.remove(), 300);
  }
}

function listenToasts() {
  listen('tauri://toast', (event) => {
    const toast = event.payload;
    showToast(toast.title, toast.body, toast.kind, toast.timeout_ms);
  });
}

// === Capture Overlay ===
function showCaptureOverlay() {
  captureOverlay.classList.remove('hidden');
  setTimeout(() => {
    captureOverlay.classList.add('active');
  }, 50);
}

function hideCaptureOverlay() {
  captureOverlay.classList.remove('active');
  setTimeout(() => {
    captureOverlay.classList.add('hidden');
  }, 300);
}

// === Utility ===
function debounce(fn, delay) {
  let timeout;
  return (...args) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}