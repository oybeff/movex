<?php
/** E3 · 500 — xato ID bilan. Sahifa yarmida yiqilsa ham karta ko'rinadi. */
$rid = $GLOBALS['errorId'] ?? 'req_unknown';
$detail = $GLOBALS['errorDetail'] ?? '';
$when = date('d.m H:i');
$card = '<div class="state-page"><div class="state-icon danger"><i data-lucide="server-crash"></i></div>'
      . '<h2>Nimadir xato ketdi</h2>'
      . '<p>Server javob bermadi. Xato ID: <b class="num">' . htmlspecialchars($rid) . '</b> · ' . $when
      . '. Muammo takrorlansa, shu ID bilan texnik guruhga yozing.</p>'
      . ($detail !== '' ? '<pre class="state-detail">' . htmlspecialchars($detail) . '</pre>' : '')
      . '<div class="state-actions"><a class="btn btn-primary" href="javascript:location.reload()">Qayta urinish</a>'
      . '<a class="btn btn-secondary" href="index.php">Dashboard</a></div></div>';
if (headers_sent()) {
    echo '<div class="content"><div class="card"><div class="card-body">' . $card . '</div></div></div>';
    return;
}
?><!DOCTYPE html>
<html lang="uz"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Xato · MoveX GO</title>
<link rel="stylesheet" href="assets/css/style.css?v=<?= @filemtime(__DIR__ . '/../assets/css/style.css') ?>"></head>
<body class="state-body"><div class="card" style="max-width:560px;margin:10vh auto"><div class="card-body"><?= $card ?></div></div>
<script src="assets/js/lucide.min.js"></script><script>lucide.createIcons()</script></body></html>
