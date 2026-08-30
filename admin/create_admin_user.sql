-- Movex GO - Admin User Yaratish
-- Bu script admin foydalanuvchi yaratadi

-- Admin user yaratish
INSERT INTO users (full_name, phone, email, password_hash, role, created_at)
VALUES (
    'Admin User',
    '+998901234567',
    'admin@movexgo.uz',
    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- password: "password"
    'admin',
    NOW()
)
ON CONFLICT (phone) DO NOTHING;

-- Admin uchun balance yaratish
INSERT INTO balances (user_id, balance, created_at, updated_at)
SELECT id, 0, NOW(), NOW()
FROM users
WHERE phone = '+998901234567' AND role = 'admin'
ON CONFLICT (user_id) DO NOTHING;

-- Natijani ko'rsatish
SELECT 
    id,
    full_name,
    phone,
    email,
    role,
    created_at
FROM users
WHERE phone = '+998901234567' AND role = 'admin';

-- MUHIM ESLATMA:
-- Default parol: "password"
-- Login qilgandan keyin parolni o'zgartiring!
--
-- Parolni o'zgartirish uchun:
-- 1. PHP orqali yangi hash yaratish:
--    php -r "echo password_hash('yangi_parol', PASSWORD_BCRYPT);"
--
-- 2. Database'da yangilash:
--    UPDATE users 
--    SET password_hash = 'yangi_hash' 
--    WHERE phone = '+998901234567' AND role = 'admin';

