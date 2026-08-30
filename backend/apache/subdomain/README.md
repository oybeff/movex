# Apache Subdomen Konfiguratsiyasi

Bu papkada subdomen uchun Apache konfiguratsiya fayllari joylashgan.

## Fayllar

- `movex.004.uz.conf` - movex.004.uz subdomen uchun Apache virtual host

## Ishlatish

### 1. Config faylini nusxalash

```bash
sudo cp apache/subdomain/movex.004.uz.conf /etc/apache2/sites-available/
```

### 2. Site ni faollashtirish

```bash
sudo a2ensite movex.004.uz.conf
```

### 3. Apache ni test qilish

```bash
sudo apache2ctl configtest
```

### 4. Apache ni qayta yuklash

```bash
sudo systemctl reload apache2
```

## Sozlamalar

Config faylida quyidagi sozlamalar mavjud:

- **ServerName**: movex.004.uz
- **Proxy**: http://127.0.0.1:8000
- **Logging**: /var/log/apache2/movex_*.log
- **Upload limit**: 20MB
- **Compression**: Yoqilgan
- **Security headers**: Sozlangan

## SSL

SSL sertifikat uchun Certbot ishlatiladi:

```bash
sudo certbot --apache -d movex.004.uz
```

Certbot avtomatik ravishda SSL konfiguratsiyasini qo'shadi.

## Muammolarni hal qilish

### Config test xatolik beradi

```bash
sudo apache2ctl configtest
```

Xatolikni ko'rsatadi va tuzatish kerak.

### Site ochilmayapti

```bash
# Apache ishlayaptimi?
sudo systemctl status apache2

# Loglarni ko'rish
sudo tail -f /var/log/apache2/movex_error.log
```

### 502 Bad Gateway

Backend (port 8000) ishlamayapti:

```bash
sudo systemctl status movex-api
sudo journalctl -u movex-api -f
```

