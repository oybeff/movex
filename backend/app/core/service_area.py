"""
Зона обслуживания (макет E3 «Xizmat hududidan tashqarida»).

Сейчас это Ташкент и Ташкентская область — прямоугольник по крайним
точкам области. Грубо, но честно: точка вне него точно вне зоны, а
внутри Сырдарьинская кромка с запада попадает — это допустимо, техника
туда всё равно доезжает. Зона одна на всё приложение; когда регионов
станет больше, сюда — список прямоугольников.
"""
from typing import Optional

AREA = {
    "name_uz": "Toshkent shahri va Toshkent viloyati",
    "name_ru": "город Ташкент и Ташкентская область",
    "min_lat": 40.30,
    "max_lat": 42.30,
    "min_lon": 68.60,
    "max_lon": 70.90,
}


def contains(lat: Optional[float], lon: Optional[float]) -> bool:
    """Точку без координат не отбрасываем — проверять нечего."""
    if lat is None or lon is None:
        return True
    return AREA["min_lat"] <= lat <= AREA["max_lat"] and AREA["min_lon"] <= lon <= AREA["max_lon"]
