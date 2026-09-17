# PosterKit — wycięte elementy do plakatu "My Travel Journey"

Stan: **wycięte i gotowe, NIE podpięte do Xcode**. Placement do kompozycji
plakatu robimy dopiero przy przebudowie `TravelJourneyPosterView.swift`
("umiesc jak bedzie sie tworzyc plakat").

Data: 11.09.2026. Źródła: 9 arkuszy AI od usera (1× "Photo Frames Collection
1/4" + 8 arkuszy dekoracji travel-scrapbook), wszystkie w czystym formacie
(elementy pojedynczo na przezroczystości, ramki mają wycięty otwór na zdjęcie).

Metoda: `_extract_deco.py` — alpha>100 → connected components → filtr
rozmiaru → watershed split dla zlepionych blobów → ciasny crop RGBA,
zachowany największy spójny blob alfy.

## Zawartość

| folder | ile | co |
|---|---|---|
| `frames/` | 15 | ramki na zdjęcia (polaroid, koło, serce, chmurka, taśma filmowa, znaczek pocztowy, trójkąt/proporczyk, zdobiona etykieta, złota rama, airmail, podarty papier, segregator, ząbkowane kółko, narożniki) |
| `deco1/`–`deco8/` | 27–41 | dekoracje: aparaty, kompasy, globusy, mapy, walizki, paszport, koperty, pocztówki, bilety, znaczki, zawieszki, washi tape, spinacze, pinezki, liście, sznurki, lupa, lornetka, klucze, samoloty, stemple, papiery |

Podgląd każdego arkusza: `<folder>/_contact.png`.

## Do dopracowania przy użyciu (nie teraz)

`frames/` — 3 pliki to sklejone grupy do rozdzielenia, 5 to nie-ramki do
pominięcia:
- `frames_00` logo PMemories, `frames_01` baner, `frames_02` tag "1/4",
  `frames_11` klaster aparat+kompas+liście, `frames_14` paszport+karta
  pokładowa → **nie ramki** (część z nich pasuje jako dekoracja).
- `frames_04` = polaroid + drewniany tamborek + liście (rozdzielić na 2–3).
- `frames_10` = chmurka + kartka z segregatora + ząbkowane kółko (rozdzielić na 3).
- `frames_06` = serce + małe czerwone serduszko (rozdzielić / przyciąć).

Reszta (`deco1`–`deco8`) wyszła czysto, bez sklejek.

Pełne pokrycie ramek dopiero po arkuszach 2/4–4/4 (user dostarczy).
