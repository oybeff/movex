"""
Material yetkazadigan mashinalar va ularni tanlash.

Nega texnika ma'lumotnomasidan alohida. U yerdagi kodlar IJARAGA
beriladigan texnika: ekskavator, kran, greyder. Bu yerda esa yukni olib
boradigan mashina kerak, va undan bitta narsa so'raladi — necha tonna
ko'taradi.

Tanlash qoidasi: bitta reysda sig'adigan ENG KICHIK mashina. Kichik
mashina arzonroq, va 500 dona g'isht uchun 25 tonnalik Howo yuborish —
mijozning pulini yoqish. Hech qaysisiga sig'masa, eng kattasi bilan bir
necha reys qilinadi.

Foydalanuvchi tanlovni O'ZGARTIRA oladi (ilovada ro'yxat ochiladi): u
yo'lni va joyni bizdan yaxshiroq biladi — tor ko'chaga Howo kirmasligi
mumkin. Lekin sig'imi yetmaydigan mashinani tanlashiga yo'l qo'yilmaydi,
aks holda yuk ortilmay qolardi.
"""
from decimal import Decimal, ROUND_CEILING
from typing import Dict, List, Optional


class DeliveryVehicle:
    def __init__(self, code: str, capacity_kg: int, name: Optional[str] = None,
                 volume_m3: Optional[Decimal] = None, base_fee: Decimal = Decimal("0"),
                 price_per_km: Optional[Decimal] = None):
        self.code = code
        self.capacity_kg = capacity_kg
        self.name = name or code
        self.volume_m3 = volume_m3
        self.base_fee = base_fee
        self.price_per_km = price_per_km


#: Zaxira ro'yxat: delivery_vehicles jadvali bo'sh yoki hali yo'q bo'lsa.
#: 23.11.2026 dan mashinalarni ADMIN yuritadi (admin/vehicles.php), ro'yxat
#: bazadan `load(db)` bilan olinadi.
#: Kichigidan kattasiga — tanlash shu tartibga tayanadi.
VEHICLES: List[DeliveryVehicle] = [
    DeliveryVehicle("labo", 700),          # Labo / Damas
    DeliveryVehicle("isuzu", 5_000),       # Isuzu
    DeliveryVehicle("kamaz", 15_000),      # KamAZ
    DeliveryVehicle("howo", 25_000),       # Howo / Shacman
]

BY_CODE: Dict[str, DeliveryVehicle] = {v.code: v for v in VEHICLES}

CODES: List[str] = [v.code for v in VEHICLES]


def is_valid(code: Optional[str]) -> bool:
    return bool(code) and code in BY_CODE


def capacity_kg(code: str) -> int:
    return BY_CODE[code].capacity_kg


class VehiclePlan:
    """Qaysi mashina va necha reys."""

    def __init__(self, vehicle: DeliveryVehicle, trips: int):
        self.vehicle = vehicle
        self.trips = trips

    @property
    def code(self) -> str:
        return self.vehicle.code

    @property
    def capacity_kg(self) -> int:
        return self.vehicle.capacity_kg


def _trips_for(weight_kg: Decimal, capacity: int) -> int:
    """Yuqoriga yaxlitlash: 0.2 reys degan narsa yo'q."""
    if weight_kg <= 0:
        return 0
    trips = (weight_kg / Decimal(capacity)).quantize(
        Decimal("1"), rounding=ROUND_CEILING
    )
    return max(1, int(trips))


def load(db) -> List[DeliveryVehicle]:
    """Yoqilgan mashinalar, sig'imi bo'yicha o'sish tartibida."""
    from app.models.catalog import DeliveryVehicleRow

    try:
        rows = (
            db.query(DeliveryVehicleRow)
            .filter(DeliveryVehicleRow.is_enabled.is_(True))
            .order_by(DeliveryVehicleRow.capacity_kg, DeliveryVehicleRow.sort_order)
            .all()
        )
    except Exception:
        db.rollback()
        rows = []
    if not rows:
        return list(VEHICLES)
    return [
        DeliveryVehicle(
            r.code, int(r.capacity_kg), r.name,
            Decimal(r.volume_m3) if r.volume_m3 is not None else None,
            Decimal(r.base_fee or 0),
            Decimal(r.price_per_km) if r.price_per_km is not None else None,
        )
        for r in rows
    ]


def choose(weight_kg: Decimal, preferred: Optional[str] = None,
           vehicles: Optional[List[DeliveryVehicle]] = None) -> VehiclePlan:
    """
    Yuk uchun mashina.

    preferred berilsa — o'sha ishlatiladi (foydalanuvchi tanlagan), lekin
    sig'imi yetmasa reyslar soni oshadi, ya'ni yuk baribir tashiladi.
    Berilmasa — bitta reysga sig'adigan eng kichigi.
    """
    vehicles = vehicles or VEHICLES
    by_code = {v.code: v for v in vehicles}
    if weight_kg <= 0:
        return VehiclePlan(vehicles[0], 0)

    if preferred and preferred in by_code:
        vehicle = by_code[preferred]
        return VehiclePlan(vehicle, _trips_for(weight_kg, vehicle.capacity_kg))

    for vehicle in vehicles:
        if weight_kg <= vehicle.capacity_kg:
            return VehiclePlan(vehicle, 1)

    # Eng kattasiga ham sig'madi — bir necha reys.
    biggest = vehicles[-1]
    return VehiclePlan(biggest, _trips_for(weight_kg, biggest.capacity_kg))
