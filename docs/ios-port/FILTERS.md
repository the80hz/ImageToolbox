# План порта фильтров на iOS

Часть фазы 4 из [TODO.md](TODO.md). Состав фич — в [FEATURES.md](FEATURES.md). Дата: 2026-10-10.

## 1. Что именно нужно портировать

Каталог `feature/filters/.../data/model`: 522 файла, по одному классу-фильтру. Параметры и
описание контрактов — `core/filters/.../domain` (интерфейс `Filter`, `FilterParam`, `TemplateFilter`,
33 класса параметров, 12 enum'ов). UI и 524 файла `presentation/model` в `core/filters` — это
Compose-обёртки над теми же фильтрами, на iOS пишутся заново, не портируются.

Чем реализованы фильтры (файлы могут попадать в несколько строк, суммировать нельзя):

| Движок на Android | Файлов | Подход на iOS |
|---|---|---|
| G'MIC (`com.t8rin.gmic`, нативная C++) | 166 | собрать G'MIC (CImg) под iOS и вызывать так же; либо портировать по частям |
| Aire (`com.awxkee.aire`, нативная) | 131 | Core Image, vImage, Accelerate; остальное — порт на Swift/Metal |
| Trickle (`com.t8rin.trickle`, ядро цветокоррекции) | 58 | порт на Swift и Metal, часть покрывается Core Image |
| ColorMatrix (Android) | 44 | `CIColorMatrix` и `vImageMatrixMultiply` |
| Jh Labs (`JhFilterTransformation`) | 39 | порт Java-алгоритмов на Swift |
| GPUImage (`jp.co.cyberagent`) | 35 | Core Image и Metal |
| Дизеринг | 21 | порт на Swift (чистая арифметика) |
| OpenCV (`lib/opencv-tools`) | 16 | OpenCV под iOS (xcframework) либо Vision и Accelerate |
| Без внешних библиотек | 123 | прямой порт Kotlin на Swift |

Вывод: Core Image покрывает меньше половины. Главный риск — **G'MIC**, треть каталога. Решение по
нему определяет весь план.

## 2. Решения до старта (блокеры)

| # | Вопрос | Варианты | Что нужно от вас |
|---|---|---|---|
| F1 | G'MIC: как получить 166 фильтров | (а) собрать `gmic`/CImg как XCFramework и вызывать из Swift; (б) переписать нужные фильтры на Metal и Swift; (в) не переносить | выбор. Рекомендую (а) для старта, (б) выборочно для самых популярных |
| F2 | Лицензия G'MIC | G'MIC распространяется под CeCILL (GPL-совместимая). Проверить совместимость с лицензией проекта и условиями App Store | подтвердить |
| F3 | OpenCV на iOS | подключить xcframework (+ около 30 МБ) или заменить Vision и Accelerate | выбор |
| F4 | Совместимость файлов шаблонов | формат `FilterParamsInteractor`/сериализации держим совместимым с Android или независимый | выбор |

До решения F1 выполняются только этапы 0–2.

## 3. Архитектура на iOS

Всё без UI — в `ios/ImageToolboxKit/Sources/ImageToolboxKit/Filters`, тесты на Swift Testing.

- `Filter` — протокол: `id`, `parameters`, `apply(to: RasterImage) async throws -> RasterImage`,
  `cacheKey`. Параметры описываются данными (`FilterParameter`: число с границами, булево, enum,
  цвет, точка, список), чтобы UI собирался автоматически.
- `FilterRegistry` — каталог: `id`, категория, ключи поиска, движок, фабрика. Идентификаторы
  берём 1 в 1 с Android, чтобы шаблоны и сообщения об ошибках совпадали.
- `FilterChain` — упорядоченный список фильтров с параметрами, `Codable`.
- `FilterTemplate` — именованная цепочка, хранение в `Library`/`Settings` пакета.
- Движки изолированы за `FilterEngine` (CoreImage, Metal, CPU, GMIC): один фильтр — один движок,
  фильтр не знает о других.
- Один общий `CIContext` и пул текстур Metal. Цепочка из Core Image-фильтров собирается в один
  граф и рендерится единожды, без промежуточных `CGImage`.
- Превью считается на уменьшенной копии (по длинной стороне 1024 пикселя), экспорт — на оригинале.
  Отмена через `Task.isCancelled`.

UI (`ios/ImageToolbox/Sources/Features/Filters`): выбор фото, список цепочки с перетаскиванием,
добавление фильтра (поиск + категории), панель параметров, сравнение до/после, шаблоны, пакетный
экспорт через уже готовый `BatchRunner`.

## 4. Этапы

Критерий готовности этапа — по общим критериям фичи из TODO.md плюс: golden-тесты на эталонных
изображениях, замер времени на 12 Мп, `swift format --strict` и без предупреждений.

### Этап 0. Каркас (без фильтров)
- [x] `Filter`, `FilterParameter`, `FilterRegistry`, `FilterChain`, `FilterTemplate` в пакете (`Sources/.../Filters`).
- [x] Сериализация цепочки и шаблонов (`Codable`), тесты на круговой обход: `FilterChainTests`.
- [x] Экран «Фильтры»: выбор фото, цепочка, параметры, превью, экспорт, пакетный режим. Собран без предупреждений, запущен в симуляторе: UI-тест `testFiltersChainShowsAddedFilter` (выбор фото, добавление «Negative», шаг цепочки, «Share file») и смоук-тест всех инструментов проходят (2026-10-10). Перетаскивание в цепочке заменено кнопками «вверх» и «вниз». Подключены образцы и все фильтры реестра (см. раздел 7).
- [~] Эталонный набор: снимки результатов Android-версии для сверки (раздел 10). Снято 27 случаев инструментальным тестом `ReferenceFilterExportTest` в Android-проекте (`feature/filters/src/androidTest`), сверка в `AndroidReferenceParityTests`. Проверено по эталону 27 фильтров, расхождений нет (`GaussianBlurFilter` и `SaturationFilter` исправлены 2026-10-13 по исходникам Aire и libblur, раздел 10). Остальные 85 фильтров эталонов не имеют. Шторка Compose в `uiautomator dump` по-прежнему не видна, поэтому управление интерфейсом не использовалось.

### Этап 1. Core Image и матрицы цвета (оценка: 80–100 фильтров)
Статус: частично, 58 фильтров (раздел 7). ColorMatrix 10 из 44, шум (`Noise`) не сделан, LookupFilter и файловые LUT не сделаны.
- [ ] Яркость, контраст, насыщенность, экспозиция, гамма, оттенок, баланс белого, уровни, тени и света.
- [ ] Размытия: гауссово, box, motion, zoom, bokeh, tilt-shift.
- [ ] Резкость, шум, виньетка, зерно, сепия, чёрно-белое, инверсия, постеризация, пикселизация.
- [ ] Все `ColorMatrix*`-фильтры (44) и дальтонизм (ахроматопсия, протаномалия и др.).
- [ ] LUT: `LookupFilter`, `LUT512x512`, `CubeLut` через `CIColorCube`. Отложено (2026-10-11), см. раздел 8.

### Этап 2. Порт на Swift и Metal без внешних зависимостей (около 120 фильтров)
Статус: частично, 54 фильтра (раздел 7). Тональная компрессия 6 из 10 (ACES Hill не сделан, три G'MIC-фильтра нет), CLAHE 2 из 13, морфология 7 из 10, глитч и CRT 2 из 15.
- [ ] Дизеринг (21): Floyd–Steinberg, Atkinson, Bayer, Burkes, Jarvis и т. д. — CPU.
- [ ] Морфология: эрозия, дилатация, открытие и закрытие, top-hat и black-hat.
- [ ] Тональная компрессия: ACES, Hable, Hejl–Burgess, Drago, логарифмическая.
- [ ] Гистограммы: Equalize, CLAHE во всех цветовых пространствах (Lab, Luv, HSL, HSV, Oklab).
- [ ] Искажения: fish eye, bulge, swirl, kaleidoscope, glass tiles, spiral, droste.
- [ ] Глитч-фильтры, CRT, эффекты плёнки и градиентные карты.
- [ ] Группы по 10–15 фильтров на коммит, каждая с golden-тестами.

### Этап 3. Aire и Trickle
- [ ] Инвентаризация: по каждому из 131 и 58 файлов — найти вызов, определить аналог Core Image,
  vImage или написать ядро Metal.
- [ ] Порт по приоритету популярности (данные `UsageTracker` и порядок в Android-UI).

### Этап 4. Маски и сложные режимы
- [ ] Маски фильтров (`FilterMask`, `FilterMaskApplier`): рисуемая маска, инверсия, порядок,
  несколько масок на одну цепочку.
- [ ] Seam Carving, Crop/Perspective, Auto-удаление красных глаз, Deskew (Vision, OpenCV).
- [ ] Фильтры, использующие несколько изображений (displacement, color transfer).

### Этап 5. G'MIC (зависит от F1)
- [ ] Сборка `gmic` под iOS (arm64, симулятор), обёртка Swift, ограничения по памяти.
- [ ] Порт `GmicFilterParams` и списка 166 фильтров; свой UI для «сырого» G'MIC-скрипта, как на Android.
- [ ] Оптимизация: превью на уменьшенной копии, фоновая очередь, лимиты памяти на 12 Мп.

### Этап 6. Шаблоны, пакетный режим, полировка
- [ ] Менеджер шаблонов, импорт и экспорт, совместимость с Android (по F4).
- [ ] Пакетное применение цепочки ко многим фото через `BatchRunner`.
- [ ] Доступность (VoiceOver для параметров), XXXL, тёмная тема, локализация en/ru.
- [ ] Профилирование и снижение памяти, UI-тесты, обновление документации.

## 5. Приёмка

- Для каждого фильтра есть запись в `FilterRegistry`, тест и строка в таблице соответствия
  (`FILTERS_PARITY`, генерируется скриптом из `data/model` Android и реестра iOS).
- Цель по покрытию: этап 1–2 — около 200 фильтров (40%), этап 3 — около 350 (70%), этап 4 — 400,
  этап 5 — полный каталог.
- Превью цепочки из 5 фильтров на 12 Мп отзывается в пределах секунды (на симуляторе — ориентир).

## 6. Риски

- G'MIC: размер бинарника, время сборки, память на больших фото, лицензия.
- Расхождение результата с Android: источник правды — эталонные снимки, допуск задаётся в тестах.
- Объём: 500+ фильтров — это недели работы, делим на PR по 10–15 фильтров.
- App Store: приложение, использующее G'MIC, должно соблюдать условия лицензии.

## 7. Статус выполнения (2026-10-11)

Реестр: 112 фильтров (на 2026-10-10 было 109; добавлены `SimpleSolarizeFilter`, `ColorMatrix3x3Filter`, `ColorMatrix4x4Filter`). Все id совпадают с именами классов `feature/filters/.../data/model`. Тесты пакета: полный прогон `swift test` 2026-10-11, см. раздел 11. Фильтры покрыты своими `*FilterTests.swift`, общим тестом крайних значений `FilterRegistryTests` и сверкой с эталонами `AndroidReferenceParityTests` (раздел 10).

Статусы:
- **проверено по эталону** — выход на эталонном входе совпал с Android в пределах допуска: среднее отличие по каналам не больше 0.25, наибольшее не больше 1 (27 фильтров, раздел 10).
- **приближение** — формула собрана по стандартной схеме, либо Android вызывает нативный код, которого в репозитории нет (85 фильтров). Расхождений с эталонами не осталось: `GaussianBlurFilter` и `SaturationFilter` перенесены по исходникам Aire и libblur и перешли в «проверено» (раздел 10).
- **перенесён** — формула взята из Android-кода, сверки с эталоном нет. Таких фильтров сейчас нет: все шесть перенесённых по формуле сверены в этом заходе.

Все приближения и проверенные фильтры помечены в doc-комментариях файла.

| Группа | Файл | Проверено по эталону | Перенесено | Приближений | Не перенесено |
|---|---|---|---|---|---|
| Яркость и цвет | `LightColourFilters.swift` | 11 | 0 | 6 | 0 |
| Размытия | `BlurFilters.swift` | 2 | 0 | 11 | 2 |
| Резкость и шум | `SharpenNoiseFilters.swift` | 2 | 0 | 4 | 5 |
| ColorMatrix и дальтонизм | `ColourMatrixFilters.swift` | 2 | 0 | 8 | 1 |
| LUT (12 пресетов) | `LUTFilters.swift` | 0 | 0 | 12 | 3 |
| Дизеринг (диффузия) | `DitheringFilters.swift` | 0 | 0 | 10 | 0 |
| Дизеринг (упорядоченный) | `OrderedDitheringFilters.swift` | 0 | 0 | 9 | 2 |
| Морфология | `MorphologyFilters.swift` | 0 | 0 | 7 | 3 |
| Тональная компрессия | `ToneMappingFilters.swift` | 0 | 0 | 6 | 4 |
| Гистограммы | `HistogramFilters.swift` | 0 | 0 | 4 | 2 |
| CLAHE | `ClaheFilters.swift` | 0 | 0 | 2 | 11 |
| Искажения | `DistortionFilters.swift` | 9 | 0 | 5 | 1 |
| Глитч и CRT | `GlitchCRTFilters.swift` | 1 | 0 | 1 | 11 (`FilmStock50` и `BleachBypass` — в LUT) |
| **Итого** | | **27** | **0** | **85** | **45** |

Проверено по эталону: `SepiaFilter`, `NegativeFilter`, `BlackAndWhiteFilter`, `SolarizeFilter`, `PosterizeFilter`, `VignetteFilter`, `SimpleSolarizeFilter`, `ExposureFilter`, `HueFilter`, `WhiteBalanceFilter`, `SaturationFilter` (Яркость и цвет); `ZoomBlurFilter`, `GaussianBlurFilter` (Размытия); `PixelationFilter`, `SharpenFilter` (Резкость); `ColorMatrix3x3Filter`, `ColorMatrix4x4Filter` (ColorMatrix); `BulgeDistortionFilter`, `SwirlDistortionFilter`, `SphereRefractionFilter`, `GlassSphereRefractionFilter`, `GlassHexTilesFilter`, `GlassRectTilesFilter`, `GlassTriangleTilesFilter`, `LogarithmicSpiralFilter`, `SpiralDrosteFilter` (Искажения); `GradientMapFilter` (Глитч и CRT).

Расхождений с эталоном нет. `GaussianBlurFilter` и `SaturationFilter` исправлены 2026-10-13 (нативный Aire прочитан в публичном репозитории awxkee/aire и libblur, раздел 10).

Перенесено по формуле и сверено с эталоном в этом заходе: `GlassHexTiles`, `GlassRectTiles`, `GlassTriangleTiles`, `LogarithmicSpiral`, `SpiralDroste` (Искажения) и `GradientMap` (Глитч и CRT).

Итого: 112 зарегистрировано: 27 проверено по эталону, 0 перенесено по формуле, 85 приближений, 45 не перенесено (раздел 8).

## 8. Не перенесено

Имя в скобках — класс Android.

- **Тональная компрессия (4):** `AcesHill` (Aire, точные матрицы не воспроизводятся надёжно по памяти); `Retinex`, `DynamicContrast`, `LocalContrastEnhancement` (G'MIC, CeCILL-C, нативный код). Шесть операторов перенесены как приближения по опубликованным формулам (см. раздел 9, решение 1).
- **LUT (3):** `Lookup`: Kotlin создаёт `GPUImageLookupFilter(value)` без второй текстуры, поведение без таблицы не восстанавливается по коду. `LUT512x512` и `CubeLut`: в Kotlin только разбор параметров и вызов `Trickle.applyLut` / `Trickle.applyCubeLut`, а Trickle — нативная библиотека (`libtrickle.so`), формулы в репозитории нет. По правилу пакета B («без нативных библиотек» и «не придумывать формулу») не переносятся; вид параметра «файл» не добавлен, потому что без фильтра он не используется. Таблицы 12 пресетов добавлены в `Resources/LUT`. **Отложено (2026-10-11) по решению пользователя.** Вернуться, когда найдётся исходник Trickle или будет решено сделать приближение через `CIColorCube` с пометкой «приближение».
- **Размытия (2):** `EnhancedZoomBlur` (семантика `angle` и `strength` в нативном Aire), `PoissonBlur` (алгоритм Aire не воспроизводим по Kotlin).
- **Резкость и шум (5):** `ConstrainedSharpen`, `AlphaSharpen` (G'MIC); `Noise` (Trickle, семантика threshold не восстанавливается); `ReduceNoise`, `Despeckle` (Jh Labs).
- **ColorMatrix (1):** `ColorAnomaly` (через `Aldridge`, Aire). `ColorMatrix3x3` и `ColorMatrix4x4` перенесены в этом заходе (вид параметра «матрица», раздел 7).
- **Перенесено в этом заходе (пакет B):** `SimpleSolarizeFilter` (Jh Labs, формула из AAR, см. раздел 9); `ColorMatrix3x3Filter` (Aire, формула из эталона); `ColorMatrix4x4Filter` (GPUImage, шейдер из AAR).
- **Упорядоченный дизеринг (2):** `PosterizedDithering` (G'MIC), `YililomaDithering` (палитра Trickle).
- **Морфология (3):** `FillHoles`, `Skeleton` (G'MIC); `Contour` (Jh Labs, не морфология).
- **Гистограммы (2):** `EqualizeLight`, `EqualizeShadow` (G'MIC).
- **CLAHE (11):** `ClaheLAB`, `ClaheLUV`, `ClaheHSL`, `ClaheHSV`, `ClaheOklab`, `ClaheOklch`, `ClaheJzazbz` и четыре цветовых варианта `EqualizeHistogramAdaptive*` (в Kotlin только вызовы Aire, формул перевода нет). Перенесены `Clahe` и `EqualizeHistogramAdaptive` в RGB.
- **Искажения (1):** `Droste` (G'MIC).
- **Глитч и CRT (11):** `EnhancedGlitch` (Aire); `BlockGlitch`, `GlitchVariant`, `CrtCurvature`, `VHS`, `VHSNtsc`, `SimpleOldTv` (Trickle); `HuffmanGlitch`, `CrtPhosphors`, `CrtScanlines` (G'MIC); `OldTv` (цепочка Aire и GPUImage).

## 9. Решения и открытые вопросы

Принятые решения (2026-10-10, по рекомендациям, согласовано с пользователем):

1. **Тональная компрессия — гибрид.** Шесть операторов (ACES Narkowicz, Hable, Hejl–Burgess, логарифмический, Uchimura, Drago) перенесены как приближения по опубликованным формулам, а не по Aire. ACES Hill не перенесён. Три G'MIC-фильтра не переносятся. Drago: отображение `threshold` на максимум яркости не сверено с Android.
2. **LUT — таблицы в ресурсах пакета.** 12 `lookup_*.webp` (512 × 512) скопированы из Android `core/resources` в `Sources/ImageToolboxKit/Resources/LUT` и подключены в `Package.swift`. Декодирование через ImageIO при каждом применении, без кэша. `CubeLut` и вид параметра «файл» откладываются.
3. **Приближения принимаются** для этапов 1–2 со статусом «приближение». Пункт «эталонный набор» остаётся невыполненным: сверка с Android по пикселям нужна отдельно.
4. **Движок.** Hue и WhiteBalance считаются на `.cpu` по формулам шейдеров GPUImage (решение 12). Vibrance и HighlightsAndShadows оставлены на `.coreImage` (Saturation с 2026-10-13 на `.cpu`, решение 13): ближайший `CIFilter` допустим, если фильтр помечен приближением. Exposure тоже на `.coreImage` (`CIColorMatrix` с множителем 2^EV совпадает с эталоном точно).

Решения 2026-10-11 (пакет A и пакет B):

5. **Формулы из AAR, а не из памяти.** Исходники GPUImage, Jh Labs и матрица Aire в репозитории отсутствуют, но их байткод лежит в AAR зависимостей, которые собирает Android. Шейдеры GPUImage (`tr` по `.class`) и методы `javap -c` дали: Solarize, Posterize, Sharpen, Vignette, Luminance, ColorInvert, ColorMatrix4x4 (GL, `transpose=false`), `SimpleSolarize` (`transferFunction`, JhLabs), Hue, WhiteBalance (вместе с `setHue`, `setTemperature` и `setTint`), SphereRefraction, GlassSphere и ZoomBlur. Матрица сепии `ColorMatrices.SEPIA` взята из `aire-0.18.1.aar`. Это код, который исполняется на Android, в репозиторий он не копируется.
6. **Aire записывает результат усечением.** Сепия: `floor` даёт 12279 точных совпадений из 12288 значений, округление 5866 расхождений. Поэтому `SepiaFilter` и `ColorMatrix3x3Filter` считают на CPU с усечением.
7. **`SolarizeFilter` и `PosterizeFilter` исправлены по шейдеру.** Прежняя версия расходилась с эталоном: Solarize среднее 67.8 и максимум 255, Posterize 25.2 и 51. Solarize инвертирует пиксели, у которых яркость (веса 0.2125, 0.7154, 0.0721) не больше порога, Posterize считает `floor(c · L + 0.5) / L`. Оба теперь совпадают с эталоном точно.
8. **`SimpleSolarizeFilter` перенесён по Java-формуле JhLabs.** Формула `2 (v − 0.5)` при `v > 0.5`, иначе `2 (0.5 − v)`, во Float, с усечением `(int)(f · 255)`. Округление округлением давало 2048 расхождений, а float32 с усечением совпадает точно. Обработка в JhLabs нативная (`libjhlabs.so`), поэтому формула проверена только эталоном.
9. **`ColorMatrix3x3Filter` через Aire.** Порядок операций и усечение подтверждены эталоном сепии и нестандартной матрицей. На нестандартной матрице остаются 236 из 12288 значений на 1 уровень (среднее 0.019). Причину не установлено; вероятно, Aire считает не так, как float32 в порядке `m0 r + m1 g + m2 b`. В допуске, записано числами.
10. **Вид параметра «матрица».** `FilterParameter.Kind.matrix(size:defaultValue:)`, значение `FilterValue.matrix`. Без диапазона, как на Android (текстовое поле через запятую). Ячейка, которую не удалось прочитать как число, получает значение по умолчанию, как на Android. Экран: сетка полей N × N, применение по Return.
11. **LUT-файлы и `Lookup` не переносятся** (раздел 8): нативный Trickle и отсутствующая таблица. Отложено (2026-10-11) по решению пользователя.
12. **Шейдеры GPUImage вместо CoreImage и приближений.** `HueFilter` — поворот в YIQ, как `HUE_FRAGMENT_SHADER`, угол `fmod(градусы, 360) · π / 180` во float32 (метод `setHue`). `WhiteBalanceFilter` — `WHITE_BALANCE_FRAGMENT_SHADER`; температура и тон переводятся как в `setTemperature` (0.00006 · (T − 5000) при T ≥ 5000, иначе 0.0004 · (T − 5000)) и `setTint` (тон / 100). GLSL-матрицы `mat3` заданы по столбцам, это учтено в коэффициентах. `SphereRefractionFilter` и `GlassSphereRefractionFilter` — `SPHERE_FRAGMENT_SHADER` и `GlassSphere`: вне круга результат чёрный (шейдер умножает на `step`), выборка билинейная с краем. `ZoomBlurFilter` — `ZOOM_BLUR_FRAGMENT_SHADER`: девять отсчётов, шаг 0.01 · (центр − пиксель) · size, веса 0.18, 0.15, 0.12, 0.09, 0.05. Эталоны после этого совпали; до переписывания расхождения записаны в разделе 10.
13. **`SaturationFilter` и `GaussianBlurFilter` перенесены по исходникам Aire (2026-10-13).** Исходники нашлись в публичном репозитории `awxkee/aire` (Rust, `aire-filters/src/palette.rs`, `blur.rs`), версия Aire в `libs.versions.toml` — 0.18.1; по `libaire_filters.so` из AAR подтверждены `colorutils-rs-0.7.5` и libblur (путь `fast-gaussian-blur`), исходник libblur взят с crates.io (0.19.4). Параметры по умолчанию Android проверены по Kotlin: Saturation `2f to true`, GaussianBlur `25f, 10f, Reflect101`, ядро `2·25+1 = 51`, `GaussianPreciseLevel.INTEGRAL` (значение 1 = `ConvolutionMode::FixedPoint`).
    - **Saturation.** Aire переводит sRGB в линейный RGB (точная формула, не LUT) и в Oklab, умножает `a` и `b` на силу, возвращается в линейный RGB, при tonemap применяет ACES Hill (`aces_hill`: матрицы 0.59719 и 1.60475, рациональная кривая), обрезает до 0...1 и кодирует в sRGB. Было: `CIColorControls` (яркостная насыщенность, флаг tonemap игнорировался), расхождение 35.5 и 111. Остаточное расхождение 0.35 (2 уровня) давало округление при записи в байт: Aire отбрасывает дробную часть. С усечением: среднее 0.035, максимум 1. Без tonemap ветка `else` в Aire отличается только пропуском ACES, она реализована тем же кодом.
    - **GaussianBlur.** Ядро libblur — значения плотности `exp(-0.5 (x/σ)²)` в целых точках, нормированные на сумму 1, а не интеграл по пикселю (прежняя версия). Кроме того, у libblur нестандартные границы. Строки при ядре от 29 собираются через `write_arena_row`, и справа от строки отражённые пиксели записаны в обратном порядке (`row.chunks_exact_mut(CN).rev()`); при ядре до 28 строки идут через `binter` с обычными краями. Столбцы при ядре до 61 считаются скользящим буфером (`filter_1d_approx_sliding_buffer`), и над первой строкой стоит копия строки 0 (предзагрузка верхнего края) независимо от режима; при ядре больше 61 столбцы идут через `make_arena_columns` с обычными краями. Левый и нижний края ведут себя по режиму. Расхождение было 1.63 и 19, теперь 0.026 и 1. Эталон есть только для ядра 51 (оба эффекта сразу); для ядер меньше 29 и больше 61 поведение взято по исходнику libblur 0.19.4 и на эталонах не проверялось, это допущение. Многопоточный путь libblur (плитки по высоте) на 64x64 не задействован; для больших изображений на устройстве края плиток считаются штатно, а верхний край картинки всё равно копируется.

Открытые вопросы:

- **Эталоны.** Снято 13 эталонов (раздел 10): 10 фильтров с параметрами по умолчанию, `SimpleSolarizeFilter` и две нестандартные матрицы. Проверено 13 фильтров; `GaussianBlurFilter` и `SaturationFilter` закрыты 2026-10-13 (решение 13). Эталонов нет у остальных 85 фильтров. Эталоны сняты на эмуляторе arm64 с программным GL (`hw.gpu.enabled=no`), на устройстве с GPU не сверялись.
- **Заголовки параметров.** У `BilaterialBlur` и `FastBilaterialBlur` подпись второго параметра («sigma») в Kotlin управляет `spatialSigma`, а `spatial_sigma` — `rangeSigma`. Значения по умолчанию сохранены, подписи стоит поправить.
- **TentBlur.** Значение по умолчанию в UI (10) и в Kotlin (15) различаются; взято значение UI.
- **Производительность.** `Bokeh`, `Median`, `Bilateral`, `FastBilateral` считают O(пикселей × ядро); LUT декодирует таблицу при каждом применении. На 12 Мп при максимальных параметрах будет медленно. Замер времени не выполнен.
- **`SimpleSolarizeFilter`** добавлен 2026-10-11 (решение 8), проверен эталоном.
- **Формат шаблонов (F4).** `FilterTemplate` сохраняется в JSON по Swift-структуре; совместимость с Android не проверялась.
- **Блокеры F1–F4** не закрыты: G'MIC, лицензии, OpenCV и формат шаблонов ждут решения пользователя.

## 10. Сверка с эталонами Android (2026-10-11)

Эталоны сняты инструментальным тестом `ReferenceFilterExportTest` (`feature/filters/src/androidTest/java/.../feature/filters/data/model/`). Тест применяет фильтры через `transform` к `reference/ui-sample.png` (64x64, байты совпадают с фикстурой UI-теста). Фильтр берётся с параметрами по умолчанию Android: конструктор без аргументов, а для процедурных фильтров значения из `ProceduralEffect`, для градиента палитра `Spectral`. Всего 27 случаев: 25 фильтров по умолчанию и две нестандартные матрицы (`*_custom`). С 2026-10-13 совпадают все 27 случаев (до этого расходились `GaussianBlurFilter` и `SaturationFilter`).

Запуск на эмуляторе `itb37` (Android API 37.0, google_apis, arm64, `hw.gpu.enabled=no`, GL через SwiftShader), JDK 21:

```bash
./gradlew :instrumentation-tests:connectedFossDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.t8rin.imagetoolbox.feature.filters.data.model.ReferenceFilterExportTest -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true
```

Флаг `leaveApksInstalledAfterRun` нужен: без него AGP удаляет приложение вместе с файлами эталонов. Забор эталонов:

```bash
adb pull /sdcard/Android/data/ru.tech.imageresizershrinker.debug/files/reference/. ios/ImageToolboxKit/Tests/ImageToolboxKitTests/Fixtures/AndroidReference/
```

Сверка: `AndroidReferenceParityTests` (Swift Testing), по каналам RGB. Допуск: среднее отличие не больше 0.25 и наибольшее не больше 1. Расхождение, которое не укладывается в допуск, записывается в тесте через `withKnownIssue` с числами; сейчас таких нет.

| Фильтр | Параметры | Среднее | Наибольшее | Статус |
|---|---|---|---|---|
| `SepiaFilter` | по умолчанию | 0.0007 | 1 | проверено (9 значений на 1 уровень) |
| `NegativeFilter` | по умолчанию | 0 | 0 | проверено, точно |
| `BlackAndWhiteFilter` | по умолчанию | 0.0059 | 1 | проверено |
| `SolarizeFilter` | порог 0.5 | 0 | 0 | проверено, точно |
| `PosterizeFilter` | 5 уровней | 0 | 0 | проверено, точно |
| `GaussianBlurFilter` | радиус 25, sigma 10, Reflect101 | 0.026 | 1 | проверено (до 2026-10-13: 1.63 и 19) |
| `PixelationFilter` | размер 25 | 0 | 0 | проверено, точно |
| `VignetteFilter` | start 0.3, end 0.75, чёрный | 0.0010 | 1 | проверено |
| `SharpenFilter` | 1 | 0 | 0 | проверено, точно |
| `SaturationFilter` | сила 2, tonemap | 0.035 | 1 | проверено (до 2026-10-13: 35.51 и 111) |
| `SimpleSolarizeFilter` | нет параметров | 0 | 0 | проверено, точно |
| `ExposureFilter` | 1 | 0 | 0 | проверено, точно |
| `HueFilter` | 90° | 0.0047 | 1 | проверено |
| `WhiteBalanceFilter` | температура 7000, тон 100 | 0.0022 | 1 | проверено |
| `BulgeDistortionFilter` | радиус 0.25, масштаб 0.5 | 0.0010 | 1 | проверено |
| `SwirlDistortionFilter` | радиус 0.5, угол 1, центр 0.5 / 0.5 | 0.0085 | 1 | проверено |
| `SphereRefractionFilter` | радиус 0.25, индекс 0.71 | 0.0026 | 1 | проверено |
| `GlassSphereRefractionFilter` | радиус 0.25, индекс 0.71 | 0.0024 | 1 | проверено |
| `ZoomBlurFilter` | центр 0.5 / 0.5, размер 5 | 0 | 0 | проверено, точно |
| `GlassHexTilesFilter` | интенсивность 0.2, искажение 0.25, частота 8 | 0.0133 | 1 | проверено |
| `GlassRectTilesFilter` | интенсивность 0.2, искажение 0.25, частота 8 | 0.0039 | 1 | проверено |
| `GlassTriangleTilesFilter` | интенсивность 0.2, искажение 0.25, частота 8 | 0.0201 | 1 | проверено |
| `LogarithmicSpiralFilter` | количество 2, интенсивность 1 | 0.0094 | 1 | проверено |
| `SpiralDrosteFilter` | интенсивность 2, искажение 0.2 | 0.0103 | 1 | проверено |
| `GradientMapFilter` | палитра Spectral | 0 | 0 | проверено, точно |
| `ColorMatrix3x3Filter` | нестандартная матрица, см. ниже | 0.0192 | 1 | проверено (236 значений на 1 уровень) |
| `ColorMatrix4x4Filter` | нестандартная матрица, см. ниже | 0 | 0 | проверено, точно |

Нестандартные матрицы (входные данные теста, по строкам, выходной канал на строку): 3x3 `1.2, -0.1, 0.0 / 0.1, 0.9, 0.05 / -0.2, 0.3, 1.1`; 4x4 `1.1, 0.0, 0.2, 0.0 / -0.1, 0.9, 0.0, 0.05 / 0.0, 0.1, 0.8, 0.0 / 0.0, 0.0, 0.0, 1.0`.

Фильтры, которые переписаны по шейдерам GPUImage 8.1.0 из AAR в этом заходе (`HueFilter`, `WhiteBalanceFilter`, `SphereRefractionFilter`, `GlassSphereRefractionFilter`, `ZoomBlurFilter`): до переписывания расхождения были такими. Hue 35.8 и 141 (HSV вместо YIQ), WhiteBalance 24.3 и 79 (CoreImage вместо формулы), SphereRefraction 106.7 и 252, GlassSphere 115.8 и 252 (линза приближённая, вне круга картинка не менялась), ZoomBlur 9.3 и 25 (10 отсчётов вместо 9 с весами шейдера). Исправлено, см. решения 5 и 12.

До исправлений первый прогон давал: Solarize 67.8 и 255, Posterize 25.2 и 51, Sepia 0.476 и 1 (округление вместо усечения). Исправлено, см. решения 6–7.

Границы этой сверки: вход один, 64x64, непрозрачный, без краёв прозрачности и больших размеров. Эталоны сняты на эмуляторе с программным GL, на устройстве с GPU не сверялись. Совпадение на этом входе проверяет формулу, но не гарантирует совпадение на всех картинках.

## 11. Проверки (2026-10-11, `swift test` и lint обновлены 2026-10-13)

Строки ниже взяты из вывода команд, запущенных на текущем дереве, после последней правки кода.

- `swift test` в `ios/ImageToolboxKit` (полный прогон, 2026-10-13): `Test run with 1512 tests in 180 suites passed after 88.969 seconds.` Известных расхождений нет (до 2026-10-13 было 4 known issues: `GaussianBlurFilter` и `SaturationFilter` в `AndroidReferenceParityTests`, по два условия на каждый). До пакета B было 1504 теста.
- `swift format lint --strict -r Sources Tests` в пакете: код выхода 0, замечаний нет.
- `swift format lint --strict -r ImageToolbox/Sources ImageToolbox/UITests` в `ios`: код выхода 0, замечаний нет.
- `xcodegen generate` в `ios`: код выхода 0. `git status` по `ios/ImageToolbox.xcodeproj` пуст: pbxproj вручную не правился и не изменился.
- `xcodebuild -scheme ImageToolbox -sdk iphonesimulator build`: `** BUILD SUCCEEDED **`, строк `warning:` в логе 0.
- UI-тест `xcodebuild test -scheme ImageToolbox -sdk iphonesimulator -destination 'platform=iOS Simulator,id=71D45EE4-8E8C-4A7E-88AD-369068B6DE68' -only-testing:ImageToolboxUITests/ImageToolboxUITests/testFiltersChainShowsAddedFilter`:
  `Test Case '-[ImageToolboxUITests.ImageToolboxUITests testFiltersChainShowsAddedFilter]' passed (21.536 seconds).` и `** TEST SUCCEEDED **`.
- Эталоны Android: `./gradlew :instrumentation-tests:connectedFossDebugAndroidTest ... ReferenceFilterExportTest` — `BUILD SUCCESSFUL`, на устройстве создано 27 PNG и `input.png`, `adb pull` забрал 28 файлов.

Проверка U+00A0 (`python3 -c "print(open('FILE','rb').read().count(b'\xc2\xa0'))"`) по всем изменённым и новым текстовым файлам даёт 0. Бинарные PNG эталонов в эту проверку не входят: в `VignetteFilter.png` встречаются байты `C2 A0` внутри сжатых данных изображения, это не текст.
