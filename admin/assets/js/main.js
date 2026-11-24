/**
 * Movex GO Admin Panel - Main JavaScript
 * jQuery va AJAX funksiyalari
 */

// Simple jQuery-like implementation
const $ = (selector) => {
    if (selector.startsWith('#')) {
        return document.getElementById(selector.slice(1));
    }
    return document.querySelectorAll(selector);
};

// AJAX helper
const ajax = {
    get: async (url) => {
        try {
            const response = await fetch(url, {
                method: 'GET',
                headers: {
                    'Content-Type': 'application/json',
                }
            });
            return await response.json();
        } catch (error) {
            console.error('AJAX GET Error:', error);
            throw error;
        }
    },
    
    post: async (url, data) => {
        try {
            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data)
            });
            return await response.json();
        } catch (error) {
            console.error('AJAX POST Error:', error);
            throw error;
        }
    },
    
    delete: async (url) => {
        try {
            const response = await fetch(url, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json',
                }
            });
            return await response.json();
        } catch (error) {
            console.error('AJAX DELETE Error:', error);
            throw error;
        }
    }
};

// Notification helper
const notify = {
    success: (message) => {
        showNotification(message, 'success');
    },
    
    error: (message) => {
        showNotification(message, 'error');
    },
    
    warning: (message) => {
        showNotification(message, 'warning');
    },
    
    info: (message) => {
        showNotification(message, 'info');
    }
};

function showNotification(message, type = 'info') {
    // Figma «Toast»: to'q fon, chapda holat ikonkasi, 3.5 s
    const stack = document.getElementById('toastStack') || document.body;
    const icons = { success: 'circle-check', error: 'circle-x', warning: 'triangle-alert', info: 'info' };
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    const ic = document.createElement('i');
    ic.setAttribute('data-lucide', icons[type] || 'info');
    const txt = document.createElement('div');
    txt.textContent = message;
    el.append(ic, txt);
    stack.appendChild(el);
    if (window.lucide) lucide.createIcons({ nodes: [ic] });
    setTimeout(() => {
        el.style.transition = 'opacity .3s';
        el.style.opacity = '0';
        setTimeout(() => el.remove(), 300);
    }, 3500);
}

// Modal helper
const modal = {
    show: (modalId) => {
        const modalEl = document.getElementById(modalId);
        if (modalEl) {
            modalEl.classList.add('active');
        }
    },
    
    hide: (modalId) => {
        const modalEl = document.getElementById(modalId);
        if (modalEl) {
            modalEl.classList.remove('active');
        }
    }
};

// Confirm dialog
function confirmAction(message, callback) {
    if (confirm(message)) {
        callback();
    }
}

// Loading spinner
function showLoading(elementId) {
    const element = document.getElementById(elementId);
    if (element) {
        element.innerHTML = '<div class="spinner"></div>';
    }
}

function hideLoading(elementId) {
    const element = document.getElementById(elementId);
    if (element) {
        element.innerHTML = '';
    }
}

// Format number
function formatNumber(num) {
    return new Intl.NumberFormat('uz-UZ').format(num);
}

// Format date
function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('uz-UZ', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit'
    });
}

document.addEventListener('DOMContentLoaded', () => {
    if (window.lucide) lucide.createIcons();

    // Telefon/planshet: menyu chapdan chiqadi, fonni bosish yopadi
    const toggleBtn = document.getElementById('toggleSidebar');
    const sidebar = document.getElementById('sidebar');
    const backdrop = document.getElementById('sidebarBackdrop');
    if (toggleBtn && sidebar) {
        toggleBtn.addEventListener('click', () => sidebar.classList.toggle('active'));
        if (backdrop) backdrop.addEventListener('click', () => sidebar.classList.remove('active'));
    }

    // Ctrl/⌘ + K — umumiy qidiruv
    const search = document.getElementById('globalSearch');
    if (search) {
        document.addEventListener('keydown', (e) => {
            if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
                e.preventDefault();
                search.focus();
                search.select();
            }
        });
    }

    // «Tizim ishlayapti»: API va baza holati, har 30 s
    const chip = document.getElementById('healthChip');
    if (chip) {
        const label = chip.querySelector('.label');
        const check = async () => {
            try {
                const r = await fetch('health.php', { cache: 'no-store' });
                const j = await r.json();
                const ok = j.api && j.db;
                chip.className = 'health-chip ' + (ok ? 'ok' : 'down');
                label.textContent = ok ? 'Tizim ishlayapti' : (!j.db ? 'Baza javob bermayapti' : 'API javob bermayapti');
            } catch (e) {
                chip.className = 'health-chip down';
                label.textContent = "Aloqa yo'q";
            }
        };
        check();
        setInterval(check, 30000);
    }
});

// Export for use in other scripts
window.$ = $;
window.ajax = ajax;
window.notify = notify;
window.modal = modal;
window.confirmAction = confirmAction;
window.showLoading = showLoading;
window.hideLoading = hideLoading;
window.formatNumber = formatNumber;
window.formatDate = formatDate;

