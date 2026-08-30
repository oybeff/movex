# 🚀 BOSHLASH - Movex.004.uz Deploy

## 📋 Sizning server ma'lumotlari:
- **Subdomen**: movex.004.uz
- **Papka**: /www/wwwroot/movex.004.uz
- **Usul**: Systemd (avtomatik qayta ishga tushadi)

---

## ⚡ VARIANT 1: Avtomatik (1 buyruq!) - ENG OSON

### 1. Loyihani serverga ko'chiring

**Local kompyuterdan:**
```bash
scp -r /path/to/movex_go_backend user@your-server:/www/wwwroot/movex.004.uz/
```

### 2. Serverga kiring va scriptni ishga tushiring

```bash
# SSH orqali serverga kirish
ssh user@your-server

# Deploy scriptni ishga tushirish
cd /www/wwwroot/movex.004.uz
sudo bash scripts/deploy_movex_004_uz.sh
```

**Tayyor!** Script hamma narsani avtomatik qiladi! 🎉

---

## 📝 VARIANT 2: Qadam-baqadam (agar script ishlamasa)

**To'liq qo'llanma:** [DEPLOY_MOVEX_004_UZ.md](DEPLOY_MOVEX_004_UZ.md)

Har bir buyruq tushuntirilgan, faqat copy-paste qiling!

---

## ✅ Deploy yakunlangandan keyin:

### 1. Tekshirish

```bash
# Service ishlayaptimi?
sudo systemctl status movex-api

# Loglarni ko'rish
sudo journalctl -u movex-api -f
```

### 2. Brauzerda ochish

- **API Docs**: https://movex.004.uz/docs
- **Health**: https://movex.004.uz/health

### 3. DNS sozlash

DNS sozlamalarida `movex.004.uz` ni server IP ga yo'naltiring:

```
Type: A
Name: movex
Value: YOUR_SERVER_IP
TTL: 3600
```

---

## 🔄 Yangilash (Update)

```bash
cd /www/wwwroot/movex.004.uz
git pull
venv/bin/pip install -r requirements.txt
venv/bin/alembic upgrade head
sudo systemctl restart movex-api
```

---

## 🛠️ Foydali buyruqlar

```bash
# Service boshqarish
sudo systemctl start movex-api      # Ishga tushirish
sudo systemctl stop movex-api       # To'xtatish
sudo systemctl restart movex-api    # Qayta ishga tushirish
sudo systemctl status movex-api     # Holat

# Loglarni ko'rish
sudo journalctl -u movex-api -f     # Real-time
sudo journalctl -u movex-api -n 100 # Oxirgi 100 ta

# Apache
sudo systemctl restart apache2
sudo tail -f /var/log/apache2/movex_error.log
```

---

## 🚨 Muammolarni hal qilish

### Service ishlamayapti

```bash
# Loglarni ko'rish
sudo journalctl -u movex-api -n 50

# Qo'lda test
cd /www/wwwroot/movex.004.uz
source venv/bin/activate
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### 502 Bad Gateway

```bash
# Backend ishlamayapti
sudo systemctl restart movex-api
sudo systemctl status movex-api
```

### Database xatolik

```bash
# PostgreSQL ishlayaptimi?
sudo systemctl status postgresql

# Database mavjudmi?
sudo -u postgres psql -l | grep movex_go
```

---

## 📞 Yordam kerakmi?

Agar biror qadam ishlamasa:

1. **Xatolik xabarini to'liq ko'rsating**
2. **Loglarni yuboring:**
   ```bash
   sudo journalctl -u movex-api -n 100 --no-pager
   ```

Men sizga yordam beraman! 😊

---

## 📚 Boshqa qo'llanmalar:

- **[DEPLOY_MOVEX_004_UZ.md](DEPLOY_MOVEX_004_UZ.md)** - Qadam-baqadam to'liq qo'llanma
- **[QUICK_START.md](QUICK_START.md)** - Umumiy tez boshlash
- **[SIMPLE_DEPLOY.md](SIMPLE_DEPLOY.md)** - Batafsil subdomen deploy
- **[DEPLOY.md](DEPLOY.md)** - Murakkab production deploy

