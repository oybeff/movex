# 📦 Deploy Qo'llanmalari - Xulosa

Bu loyihada turli xil deploy usullari uchun qo'llanmalar mavjud.

---

## 🎯 Qaysi qo'llanmani tanlash?

### ⚡ **START_HERE.md** - BOSHLANG BU YERDAN!
**Kim uchun:** Hammaga (eng oddiy usul)  
**Vaqt:** 5-10 daqiqa  
**Subdomen:** movex.004.uz  
**Papka:** /www/wwwroot/movex.004.uz  
**Usul:** Avtomatik script yoki qadam-baqadam

**Afzalliklari:**
- ✅ Eng oddiy va tez
- ✅ Avtomatik script mavjud
- ✅ Systemd bilan (avtomatik qayta ishga tushadi)
- ✅ Har bir qadam tushuntirilgan

**Ishlatish:**
```bash
cd /www/wwwroot/movex.004.uz
sudo bash scripts/deploy_movex_004_uz.sh
```

---

### 📘 **DEPLOY_MOVEX_004_UZ.md** - To'liq qadam-baqadam
**Kim uchun:** Script ishlamasa yoki qo'lda deploy qilmoqchi bo'lsangiz  
**Vaqt:** 10-15 daqiqa  
**Subdomen:** movex.004.uz  
**Papka:** /www/wwwroot/movex.004.uz

**Afzalliklari:**
- ✅ Har bir buyruq tushuntirilgan
- ✅ Nima bo'layotgani aniq
- ✅ Troubleshooting bo'limi bor
- ✅ Copy-paste qilish oson

---

### 📗 **QUICK_START.md** - Umumiy tez boshlash
**Kim uchun:** Boshqa subdomen yoki papka ishlatmoqchi bo'lsangiz  
**Vaqt:** 5-10 daqiqa  
**Subdomen:** Istalgan  
**Papka:** Istalgan

**Afzalliklari:**
- ✅ Moslashuvchan (har qanday subdomen)
- ✅ Qisqa va aniq
- ✅ Foydali buyruqlar to'plami

---

### 📕 **SIMPLE_DEPLOY.md** - Batafsil subdomen deploy
**Kim uchun:** To'liq ma'lumot kerak bo'lsa  
**Vaqt:** 15-20 daqiqa  
**Subdomen:** movex.004.uz  

**Afzalliklari:**
- ✅ Juda batafsil
- ✅ Monitoring va logging
- ✅ Backup va restore
- ✅ Security sozlamalari

---

### 📙 **DEPLOY.md** - Murakkab production deploy
**Kim uchun:** Katta production server uchun  
**Vaqt:** 30+ daqiqa  
**Papka:** /opt/movex_go/

**Afzalliklari:**
- ✅ Enterprise-level sozlamalar
- ✅ To'liq xavfsizlik
- ✅ Monitoring va alerting
- ✅ Backup strategiyasi

**Kamchiliklari:**
- ❌ Juda murakkab
- ❌ Ko'p vaqt talab qiladi

---

## 🗂️ Fayllar ro'yxati

### Deploy qo'llanmalari:
1. **START_HERE.md** ⚡ - Boshlash uchun (tavsiya etiladi!)
2. **DEPLOY_MOVEX_004_UZ.md** 📘 - Qadam-baqadam to'liq
3. **QUICK_START.md** 📗 - Umumiy tez boshlash
4. **SIMPLE_DEPLOY.md** 📕 - Batafsil subdomen deploy
5. **DEPLOY.md** 📙 - Murakkab production deploy

### Konfiguratsiya fayllari:
- **apache/subdomain/movex.004.uz.conf** - Apache virtual host
- **systemd/movex-api.service** - Systemd service (yangi)
- **systemd/movex_go.service** - Systemd service (eski)

### Scriptlar:
- **scripts/deploy_movex_004_uz.sh** - Avtomatik deploy script (yangi)
- **scripts/quick_deploy.sh** - Umumiy deploy script
- **scripts/backup.sh** - Backup script

---

## 🎯 Tavsiya qilinadigan yo'l:

### 1. Birinchi marta deploy qilish:
```
START_HERE.md → Avtomatik script ishga tushirish
```

### 2. Agar script ishlamasa:
```
DEPLOY_MOVEX_004_UZ.md → Qadam-baqadam qo'lda deploy
```

### 3. Muammo bo'lsa:
```
SIMPLE_DEPLOY.md → Troubleshooting bo'limini ko'rish
```

---

## 📊 Taqqoslash jadvali:

| Qo'llanma | Vaqt | Qiyinlik | Subdomen | Avtomatik | Tavsiya |
|-----------|------|----------|----------|-----------|---------|
| START_HERE.md | 5-10 min | ⭐ Oson | movex.004.uz | ✅ Ha | 🏆 Eng yaxshi |
| DEPLOY_MOVEX_004_UZ.md | 10-15 min | ⭐⭐ O'rta | movex.004.uz | ❌ Yo'q | ✅ Yaxshi |
| QUICK_START.md | 5-10 min | ⭐⭐ O'rta | Istalgan | ❌ Yo'q | ✅ Yaxshi |
| SIMPLE_DEPLOY.md | 15-20 min | ⭐⭐⭐ Qiyin | movex.004.uz | ❌ Yo'q | ⚠️ Kerak bo'lsa |
| DEPLOY.md | 30+ min | ⭐⭐⭐⭐ Juda qiyin | Boshqa | ❌ Yo'q | ❌ Tavsiya etilmaydi |

---

## 🚀 Tez boshlash (3 qadam):

### 1. Loyihani serverga ko'chiring
```bash
scp -r /path/to/project user@server:/www/wwwroot/movex.004.uz/
```

### 2. Serverga kiring
```bash
ssh user@server
```

### 3. Deploy qiling
```bash
cd /www/wwwroot/movex.004.uz
sudo bash scripts/deploy_movex_004_uz.sh
```

**Tayyor!** 🎉

---

## 📞 Yordam

Agar biror savol bo'lsa:

1. **START_HERE.md** ni oching
2. **DEPLOY_MOVEX_004_UZ.md** da troubleshooting bo'limini ko'ring
3. Loglarni tekshiring:
   ```bash
   sudo journalctl -u movex-api -n 100
   ```

---

## 🔄 Yangilash

Loyihani yangilash uchun:

```bash
cd /www/wwwroot/movex.004.uz
git pull
venv/bin/pip install -r requirements.txt
venv/bin/alembic upgrade head
sudo systemctl restart movex-api
```

---

## ✅ Xulosa

**Eng oddiy usul:** START_HERE.md → Avtomatik script

**Agar script ishlamasa:** DEPLOY_MOVEX_004_UZ.md → Qo'lda deploy

**Batafsil ma'lumot:** SIMPLE_DEPLOY.md

**Murakkab production:** DEPLOY.md (tavsiya etilmaydi)

---

**Omad! 🚀**

