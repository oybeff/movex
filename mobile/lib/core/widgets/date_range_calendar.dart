import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../constants/app_colors.dart';

class DateRangeCalendar extends StatefulWidget {
  final List<DateTimeRange> bookedRanges;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final Function(DateTime?, DateTime?) onDateRangeSelected;

  const DateRangeCalendar({
    super.key,
    required this.bookedRanges,
    this.initialStartDate,
    this.initialEndDate,
    required this.onDateRangeSelected,
  });

  @override
  State<DateRangeCalendar> createState() => _DateRangeCalendarState();
}

class _DateRangeCalendarState extends State<DateRangeCalendar> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
  }

  bool _isDateBooked(DateTime date) {
    for (var range in widget.bookedRanges) {
      if (date.isAfter(range.start.subtract(const Duration(days: 1))) &&
          date.isBefore(range.end.add(const Duration(days: 1)))) {
        return true;
      }
    }
    return false;
  }

  bool _isDateInRange(DateTime date) {
    if (_startDate == null || _endDate == null) return false;
    return date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
        date.isBefore(_endDate!.add(const Duration(days: 1)));
  }

  void _onDateTapped(DateTime date) {
    // Band sanani tanlab bo'lmaydi
    if (_isDateBooked(date)) {
      return;
    }

    setState(() {
      // Agar hech narsa tanlanmagan yoki ikkala sana ham tanlangan bo'lsa
      if (_startDate == null || (_startDate != null && _endDate != null && !_startDate!.isAtSameMomentAs(_endDate!))) {
        // Yangi range boshlash - birinchi sanani tanlash (1 kunlik)
        _startDate = date;
        _endDate = date;
      }
      // Agar faqat 1ta sana tanlangan bo'lsa (start == end)
      else if (_startDate != null && _endDate != null && _startDate!.isAtSameMomentAs(_endDate!)) {
        // Ikkinchi sanani tanlash
        if (date.isAtSameMomentAs(_startDate!)) {
          // Agar bir xil sanani yana bosilsa, hech narsa qilmaslik
          return;
        } else if (date.isBefore(_startDate!)) {
          // Agar oldingi sana tanlansa, start'ni o'zgartirish
          DateTime tempStart = _startDate!;
          _startDate = date;
          _endDate = tempStart;
        } else {
          // Agar keyingi sana tanlansa, end'ni o'zgartirish
          _endDate = date;
        }

        // Range ichida band sana borligini tekshirish
        if (_hasBookedDateInRange(_startDate!, _endDate!)) {
          // Agar band sana bo'lsa, faqat yangi sanani tanlash (1 kunlik)
          _startDate = date;
          _endDate = date;
        }
      }
    });

    widget.onDateRangeSelected(_startDate, _endDate);
  }

  bool _hasBookedDateInRange(DateTime start, DateTime end) {
    for (var range in widget.bookedRanges) {
      // Overlap check
      if (!(end.isBefore(range.start) || start.isAfter(range.end))) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Oy navigatsiyasi
        _buildMonthNavigation(),
        const SizedBox(height: 16),
        
        // Hafta kunlari
        _buildWeekDaysHeader(),
        const SizedBox(height: 8),
        
        // Calendar grid
        _buildCalendarGrid(),
        
        const SizedBox(height: 16),
        
        // Legend
        _buildLegend(),
      ],
    );
  }

  Widget _buildMonthNavigation() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () {
            setState(() {
              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
            });
          },
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          // LLLL — mustaqil oy nomi. MMMM ruschada qaratqich kelishigida
          // beradi: "августа 2026" o'rniga "Август 2026" kerak.
          _capitalize(DateFormat('LLLL yyyy', context.locale.toString())
              .format(_focusedMonth)),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
            });
          },
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildWeekDaysHeader() {
    final weekDays = 'common.weekdays_short'.tr().split(',');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: weekDays.map((day) => Expanded(
        child: Center(
          child: Text(
            day,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;

    // Oyning birinchi kuni qaysi hafta kuniga to'g'ri keladi (1=Dushanba, 7=Yakshanba)
    int firstWeekday = firstDayOfMonth.weekday;

    // Jami qatorlar soni
    final totalCells = firstWeekday - 1 + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (rowIndex) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (colIndex) {
            final cellIndex = rowIndex * 7 + colIndex;
            final dayNumber = cellIndex - (firstWeekday - 2);

            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const Expanded(child: SizedBox(height: 48));
            }

            final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
            final isBooked = _isDateBooked(date);
            final isInRange = _isDateInRange(date);
            final isStartDate = _startDate != null &&
                date.year == _startDate!.year &&
                date.month == _startDate!.month &&
                date.day == _startDate!.day;
            final isEndDate = _endDate != null &&
                date.year == _endDate!.year &&
                date.month == _endDate!.month &&
                date.day == _endDate!.day;
            final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 1)));

            return Expanded(
              child: GestureDetector(
                onTap: (isBooked || isPast) ? null : () => _onDateTapped(date),
                child: Container(
                  height: 48,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isStartDate || isEndDate
                        ? AppColors.primaryGreen
                        : isInRange
                            ? AppColors.primaryGreen.withOpacity(0.3)
                            : isBooked
                                ? Colors.red.withOpacity(0.1)
                                : isPast
                                    ? Colors.grey.withOpacity(0.1)
                                    : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isBooked
                          ? Colors.red.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        color: isStartDate || isEndDate
                            ? Colors.white
                            : isBooked || isPast
                                ? Colors.grey.withOpacity(0.4)
                                : Colors.black,
                        fontWeight: isStartDate || isEndDate
                            ? FontWeight.bold
                            : FontWeight.normal,
                        decoration: isBooked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildLegendItem(Colors.white, 'messages.available'.tr()),
        _buildLegendItem(Colors.red.withOpacity(0.3), 'messages.busy'.tr()),
        _buildLegendItem(AppColors.primaryGreen, 'common.selected'.tr()),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.grey.withOpacity(0.4),
              width: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
