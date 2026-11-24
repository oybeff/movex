<?php
/**
 * Yuqori paneldagi «Tizim ishlayapti» belgisi uchun: API /health javob
 * beryaptimi. Brauzer API'ga o'zi murojaat qilmaydi — lokal panel va API
 * turli manzilda, prod'da esa bir xil; server tomonda tekshirish ikkalasida
 * ham ishlaydi. Natija 20 soniya sessiyada saqlanadi.
 */
require_once 'config.php';
requireAdmin();
header('Content-Type: application/json');
header('Cache-Control: no-store');

$cached = $_SESSION['api_health'] ?? null;
if ($cached && $cached['at'] > time() - 20) {
    echo json_encode($cached);
    exit;
}

$ok = false;
$dbOk = false;
$ch = curl_init(rtrim(API_BASE_URL, '/') . '/health');
curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 3, CURLOPT_CONNECTTIMEOUT => 2]);
$body = curl_exec($ch);
$code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
if ($code === 200) {
    $j = json_decode((string) $body, true);
    $ok = is_array($j) && ($j['status'] ?? '') === 'healthy';
}
try {
    $dbOk = (bool) getDbConnection()->query('SELECT 1')->fetchColumn();
} catch (Throwable $e) {
    $dbOk = false;
}
$result = ['api' => $ok, 'db' => $dbOk, 'at' => time()];
$_SESSION['api_health'] = $result;
echo json_encode($result);
