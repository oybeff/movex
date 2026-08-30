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
    const notification = document.createElement('div');
    notification.className = `alert alert-${type}`;
    notification.style.position = 'fixed';
    notification.style.top = '20px';
    notification.style.right = '20px';
    notification.style.zIndex = '9999';
    notification.style.minWidth = '300px';
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.style.opacity = '0';
        notification.style.transition = 'opacity 0.3s';
        setTimeout(() => notification.remove(), 300);
    }, 3000);
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

// Sidebar toggle for mobile
document.addEventListener('DOMContentLoaded', () => {
    const toggleBtn = document.getElementById('toggleSidebar');
    const sidebar = document.getElementById('sidebar');
    
    if (toggleBtn && sidebar) {
        // Show toggle button on mobile
        if (window.innerWidth <= 1024) {
            toggleBtn.style.display = 'block';
        }
        
        toggleBtn.addEventListener('click', () => {
            sidebar.classList.toggle('active');
        });
        
        // Close sidebar when clicking outside on mobile
        document.addEventListener('click', (e) => {
            if (window.innerWidth <= 1024 && 
                !sidebar.contains(e.target) && 
                !toggleBtn.contains(e.target) &&
                sidebar.classList.contains('active')) {
                sidebar.classList.remove('active');
            }
        });
    }
    
    // Handle window resize
    window.addEventListener('resize', () => {
        if (toggleBtn) {
            toggleBtn.style.display = window.innerWidth <= 1024 ? 'block' : 'none';
        }
    });
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

