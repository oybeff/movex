# 🚀 Movex GO - Deploy Qo'llanmalari

## ⚡ Tez Boshlash (3 qadam)

### 1️⃣ Loyihani serverga ko'chiring
```bash
scp -r /path/to/movex_go_backend user@server:/www/wwwroot/movex.004.uz/
```

### 2️⃣ Serverga kiring
```bash
ssh user@server
```

### 3️⃣ Avtomatik deploy qiling
```bash
cd /www/wwwroot/movex.004.uz
sudo bash scripts/deploy_movex_004_uz.sh
```

**Tayyor! 🎉** API ishga tushdi: https://movex.004.uz/docs

---

## 📚 Qo'llanmalar

### 🏆 **[START_HERE.md](START_HERE.md)** - BOSHLANG BU YERDAN!
- ⚡ Eng oddiy va tez usul
- 🤖 Avtomatik script
- ⏱️ 5-10 daqiqa
- 📍 Subdomen: movex.004.uz
- 📁 Papka: /www/wwwroot/movex.004.uz

### 📘 **[DEPLOY_MOVEX_004_UZ.md](DEPLOY_MOVEX_004_UZ.md)** - Qadam-baqadam
- 📝 Har bir buyruq tushuntirilgan
- 🔧 Qo'lda deploy
- ⏱️ 10-15 daqiqa
- 🛠️ Troubleshooting bor

### 📗 **[QUICK_START.md](QUICK_START.md)** - Umumiy qo'llanma
- 🔄 Istalgan subdomen uchun
- 📦 Minimal sozlamalar
- ⏱️ 5-10 daqiqa

### 📕 **[SIMPLE_DEPLOY.md](SIMPLE_DEPLOY.md)** - Batafsil
- 📊 Monitoring va logging
- 💾 Backup va restore
- 🔐 Security sozlamalari
- ⏱️ 15-20 daqiqa

### 📙 **[DEPLOY.md](DEPLOY.md)** - Murakkab production
- 🏢 Enterprise-level
- ⚠️ Juda murakkab
- ⏱️ 30+ daqiqa
- ❌ Tavsiya etilmaydi (oddiy usullar bor)

### 📊 **[DEPLOY_SUMMARY.md](DEPLOY_SUMMARY.md)** - Taqqoslash
- 📋 Barcha qo'llanmalar taqqoslash
- 🎯 Qaysi birini tanlash kerak?
- 📈 Jadval va tavsiyalar

---

## 🗂️ Fayllar

### Konfiguratsiya:
- `apache/subdomain/movex.004.uz.conf` - Apache virtual host
- `systemd/movex-api.service` - Systemd service
- `.env.example` - Environment o'zgaruvchilari namunasi

### Scriptlar:
- `scripts/deploy_movex_004_uz.sh` - Avtomatik deploy (tavsiya!)
- `scripts/quick_deploy.sh` - Umumiy deploy
- `scripts/backup.sh` - Backup script

---

## 🎯 Qaysi usulni tanlash?

### Birinchi marta deploy qilish:
```
START_HERE.md → Avtomatik script
```

### Script ishlamasa:
```
DEPLOY_MOVEX_004_UZ.md → Qo'lda deploy
```

### Boshqa subdomen:
```
QUICK_START.md → Moslashuvchan usul
```

### Batafsil ma'lumot:
```
SIMPLE_DEPLOY.md → To'liq qo'llanma
```

---

## 📊 Taqqoslash

| Qo'llanma | Vaqt | Qiyinlik | Avtomatik | Tavsiya |
|-----------|------|----------|-----------|---------|
| START_HERE.md | 5-10 min | ⭐ Oson | ✅ | 🏆 |
| DEPLOY_MOVEX_004_UZ.md | 10-15 min | ⭐⭐ | ❌ | ✅ |
| QUICK_START.md | 5-10 min | ⭐⭐ | ❌ | ✅ |
| SIMPLE_DEPLOY.md | 15-20 min | ⭐⭐⭐ | ❌ | ⚠️ |
| DEPLOY.md | 30+ min | ⭐⭐⭐⭐ | ❌ | ❌ |

---

## 🛠️ Foydali buyruqlar

### Service boshqarish:
```bash
sudo systemctl start movex-api      # Ishga tushirish
sudo systemctl stop movex-api       # To'xtatish
sudo systemctl restart movex-api    # Qayta ishga tushirish
sudo systemctl status movex-api     # Holat
```

### Loglarni ko'rish:
```bash
sudo journalctl -u movex-api -f     # Real-time
sudo journalctl -u movex-api -n 100 # Oxirgi 100 ta
```

### Yangilash:
```bash
cd /www/wwwroot/movex.004.uz
git pull
venv/bin/pip install -r requirements.txt
venv/bin/alembic upgrade head
sudo systemctl restart movex-api
```

---

## 🚨 Muammolarni hal qilish

### Service ishlamayapti:
```bash
sudo journalctl -u movex-api -n 50
```

### 502 Bad Gateway:
```bash
sudo systemctl restart movex-api
```

### Database xatolik:
```bash
sudo systemctl status postgresql
```

**Batafsil:** [DEPLOY_MOVEX_004_UZ.md](DEPLOY_MOVEX_004_UZ.md) - Troubleshooting bo'limi

---

## 📞 Yordam

Agar muammo bo'lsa:

1. **Loglarni tekshiring:**
   ```bash
   sudo journalctl -u movex-api -n 100 --no-pager
   ```

2. **Qo'llanmalarni ko'ring:**
   - START_HERE.md
   - DEPLOY_MOVEX_004_UZ.md

3. **Config test:**
   ```bash
   sudo apache2ctl configtest
   ```

---

## ✅ Xulosa

**Eng oddiy:** START_HERE.md → Avtomatik script ⚡

**Qo'lda:** DEPLOY_MOVEX_004_UZ.md → Qadam-baqadam 📝

**Batafsil:** SIMPLE_DEPLOY.md → To'liq ma'lumot 📕

---

**Omad! 🚀**

**Subdomen:** movex.004.uz  
**API Docs:** https://movex.004.uz/docs  
**Health:** https://movex.004.uz/health

