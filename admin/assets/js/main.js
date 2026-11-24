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
    // E9: toast 5 s; xato — yopilguncha turadi (o'qilmay yo'qolmasin).
    const stack = document.getElementById('toastStack') || document.body;
    const icons = { success: 'circle-check', error: 'circle-x', warning: 'triangle-alert', info: 'info' };
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.setAttribute('role', type === 'error' ? 'alert' : 'status');
    const ic = document.createElement('i');
    ic.setAttribute('data-lucide', icons[type] || 'info');
    const txt = document.createElement('div');
    txt.textContent = message;
    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'toast-close';
    close.setAttribute('aria-label', 'Yopish');
    close.textContent = '×';
    const remove = () => { el.style.transition = 'opacity .3s'; el.style.opacity = '0'; setTimeout(() => el.remove(), 300); };
    close.addEventListener('click', remove);
    el.append(ic, txt, close);
    stack.appendChild(el);
    if (window.lucide) lucide.createIcons({ nodes: [ic] });
    if (type !== 'error') setTimeout(remove, 5000);
}
window.toastOk = (m) => showNotification(m, 'success');

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
// ---------------------------------------------------------------- P5 umumiy
document.addEventListener('DOMContentLoaded', () => {
    // Modal: [data-open="id"] ochadi, fon yoki [data-close] yopadi, Esc ham
    document.addEventListener('click', (e) => {
        const o = e.target.closest('[data-open]');
        if (o) { document.getElementById(o.dataset.open)?.classList.add('active'); return; }
        const m = e.target.closest('.modal.active');
        if (m && (e.target === m || e.target.closest('[data-close]'))) m.classList.remove('active');
    });
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') document.querySelectorAll('.modal.active').forEach(m => m.classList.remove('active'));
    });

    // [data-confirm] — o'z oynamiz (brauzer confirm() emas)
    document.addEventListener('click', (e) => {
        const b = e.target.closest('[data-confirm]');
        if (!b || b.dataset.confirmed) return;
        e.preventDefault();
        askConfirm(b.dataset.confirm, b.dataset.confirmOk || 'Tasdiqlash').then(ok => {
            if (!ok) return;
            b.dataset.confirmed = '1';
            if (b.form && b.name) {
                const h = document.createElement('input');
                h.type = 'hidden'; h.name = b.name; h.value = b.value;
                b.form.appendChild(h);
                b.form.submit();
            } else b.click();
        });
    });

    // E4 · Internet yo'q: banner, o'zgartirish tugmalari o'chadi
    let loadedAt = new Date();
    const since = document.getElementById('offlineSince');
    const setOffline = () => {
        document.body.classList.toggle('is-offline', !navigator.onLine);
        if (since) {
            const min = Math.max(0, Math.round((Date.now() - loadedAt) / 60000));
            since.textContent = min < 1 ? 'hozirgina' : min + ' daqiqa oldin';
        }
    };
    window.addEventListener('online', setOffline);
    window.addEventListener('offline', setOffline);
    setOffline();

    // E6 · Saqlanmagan o'zgarishlar: [data-dirty-guard] forma o'zgarsa —
    // sahifadan chiqishda brauzer so'raydi. Yuborilganda — so'ramaydi.
    document.querySelectorAll('form[data-dirty-guard]').forEach(f => {
        let dirty = false;
        f.addEventListener('input', () => dirty = true);
        f.addEventListener('change', () => dirty = true);
        f.addEventListener('submit', () => dirty = false);
        window.addEventListener('beforeunload', (e) => { if (dirty) { e.preventDefault(); e.returnValue = ''; } });
    });

    // E5 · 30 daqiqa harakatsizlik — server sessiyani yopadi. Sahifa ochiq
    // qolgan bo'lsa, vaqt tugaganda kirishga o'tamiz (forma yo'qolmasin
    // deb oldin ogohlantiramiz).
    if (document.body.dataset.idle) {
        const idleMs = +document.body.dataset.idle * 60000;
        let last = Date.now();
        ['click', 'keydown'].forEach(ev => document.addEventListener(ev, () => last = Date.now()));
        let warned = false;
        setInterval(() => {
            const left = idleMs - (Date.now() - last);
            if (left < 120000 && left > 0 && !warned) { warned = true; showNotification("2 daqiqadan keyin sessiya tugaydi — sahifani bosing", 'warning'); }
            if (left > 120000) warned = false;
            if (left <= 0) location.href = 'login.php?expired=1';
        }, 15000);
    }
});

function askConfirm(text, okLabel) {
    return new Promise(resolve => {
        const m = document.createElement('div');
        m.className = 'modal active';
        m.innerHTML = '<div class="modal-content" style="max-width:420px" role="alertdialog" aria-modal="true">'
            + '<div class="modal-body" style="padding-top:22px"><b style="font-size:15px;display:block;margin-bottom:6px"></b></div>'
            + '<div class="modal-footer"><button class="btn btn-secondary" data-r="0">Bekor</button>'
            + '<button class="btn btn-danger" data-r="1"></button></div></div>';
        m.querySelector('b').textContent = text;
        m.querySelector('[data-r="1"]').textContent = okLabel;
        document.body.appendChild(m);
        m.querySelector('[data-r="1"]').focus();
        m.addEventListener('click', e => {
            const b = e.target.closest('[data-r]');
            if (b || e.target === m) { m.remove(); resolve(!!(b && b.dataset.r === '1')); }
        });
    });
}
window.askConfirm = askConfirm;

window.$ = $;
window.ajax = ajax;
window.notify = notify;
window.modal = modal;
window.confirmAction = confirmAction;
window.showLoading = showLoading;
window.hideLoading = hideLoading;
window.formatNumber = formatNumber;
window.formatDate = formatDate;

