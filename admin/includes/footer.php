    </main>
</div>
<div class="toast-stack" id="toastStack" aria-live="polite"></div>
<?php if (!empty($_SESSION['toast'])): [$tt, $tm] = $_SESSION['toast']; unset($_SESSION['toast']); ?>
<script>document.addEventListener('DOMContentLoaded', () => showNotification(<?= json_encode((string) $tm, JSON_UNESCAPED_UNICODE) ?>, <?= json_encode(in_array($tt, ['success', 'error', 'warning', 'info'], true) ? $tt : 'info') ?>));</script>
<?php endif; ?>
<script src="assets/js/lucide.min.js"></script>
<script src="assets/js/main.js?v=<?= @filemtime(__DIR__ . '/../assets/js/main.js') ?>"></script>
</body>
</html>
