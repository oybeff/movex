"""
Test ma'lumotlarini qo'shish uchun script
"""
import sys
import os

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.session import SessionLocal
from app.models.app_settings import AppSettings, ContactMethod
from datetime import datetime

def add_test_data():
    db = SessionLocal()
    
    try:
        # Contact methods qo'shish
        print("Adding contact methods...")
        
        # Telefon
        phone = ContactMethod(
            type="phone",
            label="Telefon qilish",
            value="+998901234567",
            icon="phone",
            order=1,
            is_active=1
        )
        db.add(phone)
        
        # Email
        email = ContactMethod(
            type="email",
            label="Email yuborish",
            value="support@movexgo.uz",
            icon="email",
            order=2,
            is_active=1
        )
        db.add(email)
        
        # Telegram
        telegram = ContactMethod(
            type="telegram",
            label="Telegram",
            value="https://t.me/movexgo_support",
            icon="telegram",
            order=3,
            is_active=1
        )
        db.add(telegram)
        
        # WhatsApp
        whatsapp = ContactMethod(
            type="whatsapp",
            label="WhatsApp",
            value="+998901234567",
            icon="whatsapp",
            order=4,
            is_active=1
        )
        db.add(whatsapp)
        
        # Website
        website = ContactMethod(
            type="website",
            label="Veb-sayt",
            value="https://movexgo.uz",
            icon="web",
            order=5,
            is_active=1
        )
        db.add(website)
        
        db.commit()
        print("✓ Contact methods added successfully!")
        
        # Terms va Privacy Policy qo'shish
        print("\nAdding terms and privacy policy...")
        
        # Terms UZ
        terms_uz = AppSettings(
            key="terms_uz",
            value={
                "content": """FOYDALANISH SHARTLARI

1. UMUMIY QOIDALAR
Movex GO platformasidan foydalanish orqali siz ushbu shartlarga rozilik bildirasiz.

2. FOYDALANUVCHI MAJBURIYATLARI
- To'g'ri ma'lumotlar berish
- Platformadan qonuniy maqsadlarda foydalanish
- Boshqa foydalanuvchilarning huquqlarini hurmat qilish

3. XIZMAT KO'RSATISH SHARTLARI
- Texnika ijarasi shartnoma asosida amalga oshiriladi
- To'lovlar platformada belgilangan tartibda amalga oshiriladi
- Texnika holati va xavfsizligi ta'minlanishi kerak

4. MAS'ULIYAT
- Platform vositachi sifatida harakat qiladi
- Texnika egasi va mijoz o'rtasidagi nizolar tomonlar o'rtasida hal qilinadi
- Platform texnik yordam va qo'llab-quvvatlash xizmatlarini taqdim etadi

5. SHAXSIY MA'LUMOTLAR
- Foydalanuvchi ma'lumotlari maxfiy saqlanadi
- Ma'lumotlar faqat xizmat ko'rsatish uchun ishlatiladi
- Uchinchi shaxslarga ma'lumotlar berilmaydi

6. O'ZGARISHLAR
Platform o'z shartlarini o'zgartirish huquqini o'zida saqlab qoladi.

Oxirgi yangilanish: 2024-yil"""
            }
        )
        db.add(terms_uz)
        
        # Terms RU
        terms_ru = AppSettings(
            key="terms_ru",
            value={
                "content": """УСЛОВИЯ ИСПОЛЬЗОВАНИЯ

1. ОБЩИЕ ПОЛОЖЕНИЯ
Используя платформу Movex GO, вы соглашаетесь с данными условиями.

2. ОБЯЗАННОСТИ ПОЛЬЗОВАТЕЛЯ
- Предоставление достоверной информации
- Использование платформы в законных целях
- Уважение прав других пользователей

3. УСЛОВИЯ ПРЕДОСТАВЛЕНИЯ УСЛУГ
- Аренда техники осуществляется на основании договора
- Платежи производятся в порядке, установленном на платформе
- Должно быть обеспечено состояние и безопасность техники

4. ОТВЕТСТВЕННОСТЬ
- Платформа действует в качестве посредника
- Споры между владельцем техники и клиентом решаются между сторонами
- Платформа предоставляет техническую поддержку и услуги

5. ЛИЧНЫЕ ДАННЫЕ
- Данные пользователей хранятся конфиденциально
- Данные используются только для предоставления услуг
- Данные не передаются третьим лицам

6. ИЗМЕНЕНИЯ
Платформа оставляет за собой право изменять свои условия.

Последнее обновление: 2024 год"""
            }
        )
        db.add(terms_ru)
        
        # Privacy UZ
        privacy_uz = AppSettings(
            key="privacy_uz",
            value={
                "content": """MAXFIYLIK SIYOSATI

1. MA'LUMOTLAR TO'PLASH
Biz quyidagi ma'lumotlarni to'playmiz:
- Ism va familiya
- Telefon raqami
- Email manzili
- Kompaniya ma'lumotlari (texnika egalari uchun)

2. MA'LUMOTLARDAN FOYDALANISH
Ma'lumotlar quyidagi maqsadlarda ishlatiladi:
- Xizmat ko'rsatish
- Foydalanuvchilar o'rtasida aloqa o'rnatish
- Platformani yaxshilash
- Xavfsizlikni ta'minlash

3. MA'LUMOTLARNI SAQLASH
- Ma'lumotlar xavfsiz serverlarda saqlanadi
- Zamonaviy shifrlash texnologiyalari qo'llaniladi
- Faqat vakolatli xodimlar kirish huquqiga ega

4. FOYDALANUVCHI HUQUQLARI
Siz quyidagi huquqlarga egasiz:
- O'z ma'lumotlaringizni ko'rish
- Ma'lumotlarni yangilash
- Ma'lumotlarni o'chirish (hisobni o'chirish)

5. COOKIE VA KUZATUV
- Platformada cookie'lar ishlatiladi
- Foydalanuvchi tajribasini yaxshilash uchun
- Statistik ma'lumotlar to'plash uchun

6. ALOQA
Maxfiylik bilan bog'liq savollar uchun:
Email: privacy@movexgo.uz
Telefon: +998901234567

Oxirgi yangilanish: 2024-yil"""
            }
        )
        db.add(privacy_uz)
        
        # Privacy RU
        privacy_ru = AppSettings(
            key="privacy_ru",
            value={
                "content": """ПОЛИТИКА КОНФИДЕНЦИАЛЬНОСТИ

1. СБОР ДАННЫХ
Мы собираем следующие данные:
- Имя и фамилия
- Номер телефона
- Email адрес
- Данные компании (для владельцев техники)

2. ИСПОЛЬЗОВАНИЕ ДАННЫХ
Данные используются для следующих целей:
- Предоставление услуг
- Установление связи между пользователями
- Улучшение платформы
- Обеспечение безопасности

3. ХРАНЕНИЕ ДАННЫХ
- Данные хранятся на защищенных серверах
- Применяются современные технологии шифрования
- Только уполномоченные сотрудники имеют доступ

4. ПРАВА ПОЛЬЗОВАТЕЛЯ
Вы имеете следующие права:
- Просмотр своих данных
- Обновление данных
- Удаление данных (удаление аккаунта)

5. COOKIE И ОТСЛЕЖИВАНИЕ
- На платформе используются cookie
- Для улучшения пользовательского опыта
- Для сбора статистических данных

6. КОНТАКТЫ
По вопросам конфиденциальности:
Email: privacy@movexgo.uz
Телефон: +998901234567

Последнее обновление: 2024 год"""
            }
        )
        db.add(privacy_ru)
        
        db.commit()
        print("✓ Terms and privacy policy added successfully!")
        
        print("\n✅ All test data added successfully!")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    add_test_data()

