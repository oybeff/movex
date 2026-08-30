from sqlalchemy.orm import Session
from sqlalchemy import func
from app.models.order import Order
from app.models.balance import Balance, BalanceTransaction
from app.models.budget_reserve import BudgetReserve
from app.models.equipment import Equipment
from app.schemas.order import OrderCreate, OrderUpdate
from app.services import pricing_service
from fastapi import HTTPException
from decimal import Decimal
from datetime import datetime, date
from typing import Optional
from collections import defaultdict


def create_order(db: Session, order: OrderCreate, user_id: int):
    """
    Yangi buyurtma yaratish

    1. Balansni tekshirish
    2. Texnikaning holatini tekshirish (faqat 'available' bo'lishi kerak)
    3. Sana bo'yicha bandlikni tekshirish (overlap check)
    4. Pul muzlatish (frozen_balance ga qo'shish)
    5. Order yaratish (status='pending', frozen_amount=total_amount)

    MUHIM: Texnika avtomatik 'busy' holatiga o'tmaydi!
    Owner texnikani qo'lda 'busy' yoki 'maintenance' holatiga o'tkazishi mumkin.
    """
    # 1. Balansni olish yoki yaratish
    balance = db.query(Balance).filter(Balance.user_id == user_id).first()
    if not balance:
        balance = Balance(user_id=user_id, balance=Decimal('0.0'), frozen_balance=Decimal('0.0'))
        db.add(balance)
        db.commit()
        db.refresh(balance)

    # 2. Equipment ni tekshirish
    equipment = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
    if not equipment:
        raise HTTPException(status_code=404, detail="Texnika topilmadi")

    # 3. Texnikaning holatini tekshirish (faqat 'available' bo'lishi kerak)
    if equipment.status != 'available':
        status_messages = {
            'busy': "Texnika hozirda band (owner tomonidan belgilangan)",
            'maintenance': "Texnika ta'mirda"
        }
        message = status_messages.get(equipment.status, "Texnika mavjud emas")
        raise HTTPException(status_code=400, detail=message)

    # 4. Sana bo'yicha bandlikni tekshirish (overlap check)
    # Overlap logic: (start1 <= end2) AND (end1 >= start2)
    conflicting_orders = db.query(Order).filter(
        Order.equipment_id == order.equipment_id,
        Order.status.in_(["pending", "confirmed"]),
        Order.start_date <= order.end_date,
        Order.end_date >= order.start_date
    ).all()

    if conflicting_orders:
        conflict_details = ", ".join([
            f"#{o.id} ({o.start_date} - {o.end_date})"
            for o in conflicting_orders
        ])
        raise HTTPException(
            status_code=400,
            detail=f"Bu sana oralig'ida texnika band. To'qnashuvchi buyurtmalar: {conflict_details}"
        )

    # 5. Narxni SERVERDA hisoblash.
    # Mijoz yuborgan total_amount va commission e'tiborga OLINMAYDI —
    # ularni o'zgartirib, texnikani tekinga olish mumkin edi.
    try:
        price = pricing_service.calculate_order_price(
            db=db,
            equipment=equipment,
            start_date=order.start_date,
            end_date=order.end_date,
            delivery_latitude=order.delivery_latitude,
            delivery_longitude=order.delivery_longitude,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    total_amount = price.total

    # 6. Balansni tekshirish va pulni muzlatish.
    # Qatorni bloklaymiz: bir vaqtda kelgan ikkita buyurtma bitta mablag'ni
    # ikki marta muzlatib yubormasligi kerak.
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == user_id)
        .with_for_update()
        .one()
    )
    available_balance = balance.balance - balance.frozen_balance

    if available_balance < total_amount:
        raise HTTPException(
            status_code=400,
            detail=f"Hisobingizda yetarli mablag' yo'q. Mavjud: {float(available_balance)} so'm, Kerak: {float(total_amount)} so'm"
        )

    balance.frozen_balance += total_amount

    # 7. Order yaratish — barcha pul maydonlari server hisobidan
    order_data = order.dict()
    order_data['user_id'] = user_id
    order_data['status'] = 'pending'
    order_data['total_amount'] = total_amount
    order_data['commission'] = price.commission
    order_data['delivery_distance'] = price.delivery_distance
    order_data['delivery_fee'] = price.delivery_fee
    order_data['frozen_amount'] = total_amount

    db_order = Order(**order_data)
    db.add(db_order)

    # MUHIM: Equipment ni 'busy' holatiga O'TKAZMAYMIZ!
    # Owner o'zi qo'lda boshqaradi

    db.commit()
    db.refresh(db_order)

    return db_order


def get_order(db: Session, order_id: int):
    """Bitta buyurtmani olish"""
    return db.query(Order).filter(Order.id == order_id).first()


def get_orders(db: Session, skip: int = 0, limit: int = 100):
    """Barcha buyurtmalarni olish"""
    return db.query(Order).offset(skip).limit(limit).all()


def update_order(db: Session, order_id: int, order: OrderUpdate, current_user_id: int):
    """
    Buyurtmani yangilash (faqat status o'zgartiriladi)

    ESCROW TIZIMI: Pul xavfsizligi uchun pul faqat 'completed' holatda owner'ga o'tadi.

    Status o'zgarishlari:
    - pending -> confirmed: Egasi tasdiqladi, pul ESCROW'da qoladi (frozen_balance)
    - pending -> rejected: Egasi rad etdi, pul client'ga qaytariladi, equipment 'available' bo'ladi
    - pending -> cancelled: Client bekor qildi, pul client'ga qaytariladi, equipment 'available' bo'ladi
    - confirmed -> completed: Ish yakunlandi, pul ESCROW'dan owner'ga o'tadi
    - confirmed -> cancelled: Owner yoki client bekor qildi, pul ESCROW'dan client'ga qaytariladi
    """
    db_order = db.query(Order).filter(Order.id == order_id).first()
    if not db_order:
        raise HTTPException(status_code=404, detail="Buyurtma topilmadi")

    # Faqat status o'zgartiriladi
    if order.status is None:
        raise HTTPException(status_code=400, detail="Status ko'rsatilishi kerak")

    old_status = db_order.status
    new_status = order.status

    # Status o'zgarishini tekshirish
    if old_status == new_status:
        return db_order

    # Equipment ni olish
    equipment = db.query(Equipment).filter(Equipment.id == db_order.equipment_id).first()
    if not equipment:
        raise HTTPException(status_code=404, detail="Texnika topilmadi")

    # Balance ni olish
    balance = db.query(Balance).filter(Balance.user_id == db_order.user_id).first()
    if not balance:
        raise HTTPException(status_code=404, detail="Balans topilmadi")

    # pending -> confirmed: Egasi tasdiqladi (PUL ESCROW'DA QOLADI)
    if old_status == 'pending' and new_status == 'confirmed':
        # Equipment egasi ekanligini tekshirish
        if equipment.owner_id != current_user_id:
            raise HTTPException(status_code=403, detail="Faqat texnika egasi tasdiqlashi mumkin")

        # ESCROW: Pul frozen_balance'da qoladi, owner'ga o'tmaydi
        # Faqat status o'zgaradi
        db_order.status = 'confirmed'

        # Tranzaksiya yaratmaymiz, chunki pul hali o'tmagan

    # pending -> rejected: Egasi rad etdi
    elif old_status == 'pending' and new_status == 'rejected':
        # Equipment egasi ekanligini tekshirish
        if equipment.owner_id != current_user_id:
            raise HTTPException(status_code=403, detail="Faqat texnika egasi rad etishi mumkin")

        # Muzlatilgan pulni qaytarish
        balance.frozen_balance -= db_order.frozen_amount

        # Client uchun 'refund' transaksiyasi yaratish
        refund_transaction = BalanceTransaction(
            user_id=db_order.user_id,
            amount=db_order.frozen_amount,
            type='refund',
            status='completed',
            description=f"Buyurtma #{db_order.id} rad etildi - {equipment.type} {equipment.model}",
            order_id=db_order.id
        )
        db.add(refund_transaction)

        # MUHIM: Equipment ni 'available' holatiga QAYTARMAYMIZ!
        # Owner o'zi qo'lda boshqaradi

        # Status o'zgartirish
        db_order.status = 'rejected'
        db_order.frozen_amount = Decimal('0.0')

    # pending -> cancelled: Client bekor qildi
    elif old_status == 'pending' and new_status == 'cancelled':
        # Client ekanligini tekshirish
        if db_order.user_id != current_user_id:
            raise HTTPException(status_code=403, detail="Faqat buyurtma egasi bekor qilishi mumkin")

        # Muzlatilgan pulni qaytarish
        balance.frozen_balance -= db_order.frozen_amount

        # Client uchun 'refund' transaksiyasi yaratish
        refund_transaction = BalanceTransaction(
            user_id=db_order.user_id,
            amount=db_order.frozen_amount,
            type='refund',
            status='completed',
            description=f"Buyurtma #{db_order.id} bekor qilindi - {equipment.type} {equipment.model}",
            order_id=db_order.id
        )
        db.add(refund_transaction)

        # MUHIM: Equipment ni 'available' holatiga QAYTARMAYMIZ!
        # Owner o'zi qo'lda boshqaradi

        # Status o'zgartirish
        db_order.status = 'cancelled'
        db_order.frozen_amount = Decimal('0.0')

    # confirmed -> completed: Ish yakunlandi (PUL ESCROW'DAN OWNER'GA VA BUDJETGA O'TADI)
    elif old_status == 'confirmed' and new_status == 'completed':
        # Owner yoki client yakunlashi mumkin
        if db_order.user_id != current_user_id and equipment.owner_id != current_user_id:
            raise HTTPException(status_code=403, detail="Faqat buyurtma egasi yoki texnika egasi yakunlashi mumkin")

        # ESCROW'dan owner'ga va budjetga pul o'tkazish
        owner_balance = db.query(Balance).filter(Balance.user_id == equipment.owner_id).first()
        if not owner_balance:
            owner_balance = Balance(user_id=equipment.owner_id, balance=Decimal('0.0'), frozen_balance=Decimal('0.0'))
            db.add(owner_balance)

        # Client'dan pulni YECHIB OLISH.
        # Muzlatishni bekor qilishning o'zi yetarli emas: buyurtma yakunlanganda
        # pul mijozdan butunlay chiqib ketishi kerak. frozen_balance'ni kamaytirib,
        # balance'ga tegmaslik — pulni yo'qdan bor qilish demakdir.
        # (rad etish va bekor qilish shoxobchalarida esa aksincha: u yerda faqat
        #  muzlatish olib tashlanadi, pul mijozda qoladi.)
        balance.frozen_balance -= db_order.frozen_amount
        balance.balance -= db_order.frozen_amount

        # Pulni taqsimlash:
        # - commission budjetga
        # - qolgan qism owner'ga
        commission_amount = Decimal(str(db_order.commission))
        owner_amount = db_order.frozen_amount - commission_amount

        # Owner'ga qo'shish (faqat 90%)
        owner_balance.balance += owner_amount

        # Budjetga komissiyani saqlash.
        # Nol summani jadval qabul qilmaydi (check_budget_reserve_amount), shuning
        # uchun komissiya bo'lmasa yozuv umuman yaratilmaydi — aks holda buyurtma
        # 500 xato bilan 'confirmed' holatida abadiy qotib qolar edi.
        if commission_amount > 0:
            budget_reserve = BudgetReserve(
                order_id=db_order.id,
                amount=commission_amount,
                description=f"Buyurtma #{db_order.id} dan komissiya - {equipment.type} {equipment.model}"
            )
            db.add(budget_reserve)

        # Client uchun 'payment' transaksiyasi yaratish (to'liq summa)
        client_transaction = BalanceTransaction(
            user_id=db_order.user_id,
            amount=db_order.frozen_amount,
            type='payment',
            status='completed',
            description=f"Buyurtma #{db_order.id} yakunlandi - {equipment.type} {equipment.model}",
            order_id=db_order.id
        )
        db.add(client_transaction)

        # Owner uchun 'income' transaksiyasi yaratish (faqat 90%)
        owner_transaction = BalanceTransaction(
            user_id=equipment.owner_id,
            amount=owner_amount,
            type='income',
            status='completed',
            description=f"Buyurtma #{db_order.id} dan daromad (90%) - {equipment.type} {equipment.model}",
            order_id=db_order.id
        )
        db.add(owner_transaction)

        # MUHIM: Equipment ni 'available' holatiga QAYTARMAYMIZ!
        # Owner o'zi qo'lda boshqaradi

        # Status o'zgartirish
        db_order.status = 'completed'
        db_order.frozen_amount = Decimal('0.0')

    # confirmed -> cancelled: Tasdiqlangan buyurtma bekor qilindi (PUL ESCROW'DAN CLIENT'GA QAYTADI)
    elif old_status == 'confirmed' and new_status == 'cancelled':
        # Owner yoki client bekor qilishi mumkin
        if db_order.user_id != current_user_id and equipment.owner_id != current_user_id:
            raise HTTPException(status_code=403, detail="Faqat buyurtma egasi yoki texnika egasi bekor qilishi mumkin")

        # Agar frozen_amount 0 bo'lsa, demak pul allaqachon o'tgan (eski kod bilan yaratilgan buyurtma)
        # Bu holda owner'dan client'ga qaytarish kerak
        if db_order.frozen_amount == Decimal('0.0'):
            # Eski tizim: pul allaqachon owner'ga o'tgan
            owner_balance = db.query(Balance).filter(Balance.user_id == equipment.owner_id).first()
            if not owner_balance:
                raise HTTPException(status_code=404, detail="Owner balansi topilmadi")

            # Owner balansida yetarli pul borligini tekshirish
            if owner_balance.balance < db_order.total_amount:
                raise HTTPException(
                    status_code=400,
                    detail="Owner balansida yetarli mablag' yo'q. Buyurtmani bekor qilib bo'lmaydi."
                )

            # Owner'dan pulni ayirish
            owner_balance.balance -= db_order.total_amount

            # Client'ga pulni qaytarish
            balance.balance += db_order.total_amount

            # Owner uchun 'payment' transaksiyasi (chiqim)
            owner_refund_transaction = BalanceTransaction(
                user_id=equipment.owner_id,
                amount=db_order.total_amount,
                type='payment',
                status='completed',
                description=f"Buyurtma #{db_order.id} bekor qilindi - {equipment.type} {equipment.model} (qaytarildi)",
                order_id=db_order.id
            )
            db.add(owner_refund_transaction)

            # Client uchun 'refund' transaksiyasi (kirim)
            client_refund_transaction = BalanceTransaction(
                user_id=db_order.user_id,
                amount=db_order.total_amount,
                type='refund',
                status='completed',
                description=f"Buyurtma #{db_order.id} bekor qilindi - {equipment.type} {equipment.model}",
                order_id=db_order.id
            )
            db.add(client_refund_transaction)

        else:
            # Yangi tizim: pul escrow'da (frozen_balance'da)
            # ESCROW'dan client'ga pul qaytarish
            balance.frozen_balance -= db_order.frozen_amount

            # Client uchun 'refund' transaksiyasi yaratish
            refund_transaction = BalanceTransaction(
                user_id=db_order.user_id,
                amount=db_order.frozen_amount,
                type='refund',
                status='completed',
                description=f"Buyurtma #{db_order.id} bekor qilindi - {equipment.type} {equipment.model}",
                order_id=db_order.id
            )
            db.add(refund_transaction)

        # MUHIM: Equipment ni 'available' holatiga QAYTARMAYMIZ!
        # Owner o'zi qo'lda boshqaradi

        # Status o'zgartirish
        db_order.status = 'cancelled'
        db_order.frozen_amount = Decimal('0.0')

    else:
        raise HTTPException(
            status_code=400,
            detail=f"Noto'g'ri status o'zgarishi: {old_status} -> {new_status}"
        )

    db.commit()
    db.refresh(db_order)
    return db_order


def delete_order(db: Session, order_id: int):
    """Buyurtmani o'chirish"""
    db_order = db.query(Order).filter(Order.id == order_id).first()
    if db_order:
        db.delete(db_order)
        db.commit()
    return db_order


def get_order_statistics(
    db: Session,
    owner_id: int,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    status: Optional[str] = None,
    equipment_id: Optional[int] = None
):
    """
    Buyurtmalar statistikasini olish (faqat owner uchun)
    """
    # Owner'ning texnikalarini olish
    owner_equipment_ids = db.query(Equipment.id).filter(
        Equipment.owner_id == owner_id
    ).all()
    owner_equipment_ids = [eq[0] for eq in owner_equipment_ids]

    if not owner_equipment_ids:
        return {
            "total_orders": 0,
            "total_income": 0.0,
            "orders_by_status": {},
            "orders_by_date": [],
            "orders_by_equipment": [],
            "average_order_value": 0.0
        }

    # Base query
    query = db.query(Order).filter(Order.equipment_id.in_(owner_equipment_ids))

    # Filters
    if start_date:
        query = query.filter(Order.created_at >= datetime.combine(start_date, datetime.min.time()))
    if end_date:
        query = query.filter(Order.created_at <= datetime.combine(end_date, datetime.max.time()))
    if status:
        query = query.filter(Order.status == status)
    if equipment_id:
        query = query.filter(Order.equipment_id == equipment_id)

    orders = query.all()

    # Statistikalarni hisoblash
    total_orders = len(orders)
    # Owner uchun faqat 90% (komissiyasiz) ko'rsatamiz
    total_income = sum(float(order.total_amount) - float(order.commission) for order in orders if order.status in ['confirmed', 'completed'])

    # Status bo'yicha
    orders_by_status = defaultdict(int)
    for order in orders:
        orders_by_status[order.status] += 1

    # Sana bo'yicha (kunlik)
    orders_by_date = defaultdict(int)
    for order in orders:
        date_key = order.created_at.date().isoformat()
        if order.status in ['confirmed', 'completed']:
            orders_by_date[date_key] += 1

    orders_by_date_list = [
        {"date": date_str, "count": count}
        for date_str, count in sorted(orders_by_date.items())
    ]

    # Texnika bo'yicha
    orders_by_equipment_dict = defaultdict(lambda: {"count": 0, "income": 0.0, "equipment_name": ""})
    for order in orders:
        equipment = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
        if equipment:
            key = order.equipment_id
            orders_by_equipment_dict[key]["count"] += 1
            if order.status in ['confirmed', 'completed']:
                # Owner uchun faqat 90% (komissiyasiz)
                owner_income = float(order.total_amount) - float(order.commission)
                orders_by_equipment_dict[key]["income"] += owner_income
            orders_by_equipment_dict[key]["equipment_name"] = f"{equipment.type} {equipment.model}"
            orders_by_equipment_dict[key]["equipment_id"] = equipment.id

    orders_by_equipment_list = [
        {
            "equipment_id": data["equipment_id"],
            "equipment_name": data["equipment_name"],
            "count": data["count"],
            "income": data["income"]
        }
        for data in orders_by_equipment_dict.values()
    ]

    # O'rtacha buyurtma qiymati
    average_order_value = total_income / total_orders if total_orders > 0 else 0.0

    return {
        "total_orders": total_orders,
        "total_income": total_income,
        "orders_by_status": dict(orders_by_status),
        "orders_by_date": orders_by_date_list,
        "orders_by_equipment": orders_by_equipment_list,
        "average_order_value": average_order_value
    }
