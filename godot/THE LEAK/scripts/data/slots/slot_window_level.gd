@tool
class_name SlotWindowLevel
extends Resource
## Уровень прокачки окна KILLBOX (1×3 → 2×3 → 3×3 → 3×4 → 3×5). Первый в списке — стартовый.

## Рядов в окне.
@export_range(1, 3, 1) var rows := 3
## Барабанов в окне.
@export_range(1, 5, 1) var reels := 3
## Цена перехода на этот уровень, монет (у первого — 0).
@export_range(0, 100000, 1, "or_greater") var price := 0
## Сколько первых символов из списка «Символы» в игре на этом уровне (остальные не выпадают и скрыты на доске).
@export_range(1, 10, 1) var symbols := 3
## Гарантов одного символа за крутку — не больше стольких на этом уровне.
@export_range(0, 10, 1) var guarantee_max := 1
