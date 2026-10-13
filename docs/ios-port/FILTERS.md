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
- **проверено по эталону** — выход на эталонном входе совпал с Android в пределах допуска: среднее отличие по каналам не больше 0.25, наибольшее не больше 1 (85 фильтров, раздел 10).
- **приближение** — формула собрана по стандартной схеме, либо Android вызывает нативный код, которого в репозитории нет (27 фильтров). Эталоны сняты для всех, кроме `GrainFilter` и `RandomDitheringFilter` (недетерминированы); 25 случаев расходятся с Android, числа в разделе 10. `GaussianBlurFilter` и `SaturationFilter` перенесены по исходникам Aire и libblur и перешли в «проверено», `BrightnessFilter` и `SimpleThresholdDitheringFilter` совпали с эталоном при первой сверке (2026-10-13). Восемь фильтров дальтонизма перешли в «проверено» 2026-10-13 после замены матриц на константы `ColorMatrices.Assistance` из Aire 0.18.1 и применения через `apply3x3`. Ещё 17 фильтров перешли в «проверено» 2026-10-13 (пакет 2, решение 14): 12 LUT-пресетов (Trickle 1.9.3 `applyLut`), `ContrastFilter`, `UchimuraFilter`, `UnsharpFilter` (Aire 0.18.1), `LevelsFilter` и `TwirlFilter` (Jh Labs 8.1.0). Ещё 13 фильтров перешли в «проверено» 2026-10-13 (пакет 3a, решение 15): `GammaFilter`, `VibranceFilter`, пять операторов тональной компрессии (ACES, Hable, Hejl–Burgess, логарифмический, Drago; Uchimura проверен в пакете 2), `EqualizeFilter` (Jh Labs 8.1.0) и пять Aire-фильтров гистограмм (`EqualizeHistogramFilter`, `EqualizeHistogramHSVFilter`, `EqualizeHistogramPixelationFilter`, `EqualizeHistogramAdaptiveFilter`, `ClaheFilter`). Ещё 18 фильтров перешли в «проверено» 2026-10-13 (пакет 3b, решение 16): семь фильтров морфологии и `BokehFilter` (Aire 0.18.1, `fast_morphology` 0.3.1), `BoxBlurFilter`, `TentBlurFilter`, `NativeStackBlurFilter`, `MedianBlurFilter`, `BilaterialBlurFilter`, `FastBilaterialBlurFilter`, `MotionBlurFilter` (libblur 0.19.4 через Aire), `LinearTiltShiftFilter`, `RadialTiltShiftFilter` (Aire 0.18.1) и `FastBlurFilter` (Trickle 1.9.3). `GaussianBlurFilter` теперь точен (среднее 0, наибольшее 0) на всех трёх эталонах: ядрах 11, 51 и 81.
- **перенесён** — формула взята из Android-кода, сверки с эталоном нет. Таких фильтров сейчас нет: все шесть перенесённых по формуле сверены в этом заходе.

Все приближения и проверенные фильтры помечены в doc-комментариях файла.

| Группа | Файл | Проверено по эталону | Перенесено | Приближений | Не перенесено |
|---|---|---|---|---|---|
| Яркость и цвет | `LightColourFilters.swift` | 16 | 0 | 1 | 0 |
| Размытия | `BlurFilters.swift` | 13 | 0 | 0 | 2 |
| Резкость и шум | `SharpenNoiseFilters.swift` | 3 | 0 | 3 | 5 |
| ColorMatrix и дальтонизм | `ColourMatrixFilters.swift` | 10 | 0 | 0 | 1 |
| LUT (12 пресетов) | `LUTFilters.swift` | 12 | 0 | 0 | 3 |
| Дизеринг (диффузия) | `DitheringFilters.swift` | 0 | 0 | 10 | 0 |
| Дизеринг (упорядоченный) | `OrderedDitheringFilters.swift` | 1 | 0 | 8 | 2 |
| Морфология | `MorphologyFilters.swift` | 7 | 0 | 0 | 3 |
| Тональная компрессия | `ToneMappingFilters.swift` | 6 | 0 | 0 | 4 |
| Гистограммы | `HistogramFilters.swift` | 4 | 0 | 0 | 2 |
| CLAHE | `ClaheFilters.swift` | 2 | 0 | 0 | 11 |
| Искажения | `DistortionFilters.swift` | 10 | 0 | 4 | 1 |
| Глитч и CRT | `GlitchCRTFilters.swift` | 1 | 0 | 1 | 11 (`FilmStock50` и `BleachBypass` — в LUT) |
| **Итого** | | **85** | **0** | **27** | **45** |

Проверено по эталону: `SepiaFilter`, `NegativeFilter`, `BlackAndWhiteFilter`, `SolarizeFilter`, `PosterizeFilter`, `VignetteFilter`, `SimpleSolarizeFilter`, `ExposureFilter`, `HueFilter`, `WhiteBalanceFilter`, `SaturationFilter`, `BrightnessFilter`, `ContrastFilter`, `LevelsFilter`, `GammaFilter`, `VibranceFilter` (Яркость и цвет); `ZoomBlurFilter`, `GaussianBlurFilter`, `BoxBlurFilter`, `TentBlurFilter`, `NativeStackBlurFilter`, `MedianBlurFilter`, `BilaterialBlurFilter`, `FastBilaterialBlurFilter`, `MotionBlurFilter`, `BokehFilter`, `LinearTiltShiftFilter`, `RadialTiltShiftFilter`, `FastBlurFilter` (Размытия); `DilationFilter`, `ErodeFilter`, `OpeningFilter`, `ClosingFilter`, `TopHatFilter`, `BlackHatFilter`, `MorphologicalGradientFilter` (Морфология); `PixelationFilter`, `SharpenFilter`, `UnsharpFilter` (Резкость); `ColorMatrix3x3Filter`, `ColorMatrix4x4Filter`, `ProtanopiaFilter`, `DeuteranopiaFilter`, `TritanopiaFilter`, `AchromatopsiaFilter`, `ProtonomalyFilter`, `DeutaromalyFilter`, `TritonomalyFilter`, `AchromatomalyFilter` (ColorMatrix и дальтонизм); `BulgeDistortionFilter`, `SwirlDistortionFilter`, `SphereRefractionFilter`, `GlassSphereRefractionFilter`, `GlassHexTilesFilter`, `GlassRectTilesFilter`, `GlassTriangleTilesFilter`, `LogarithmicSpiralFilter`, `SpiralDrosteFilter`, `TwirlFilter` (Искажения); `GradientMapFilter` (Глитч и CRT); `SimpleThresholdDitheringFilter` (Дизеринг, упорядоченный); `UchimuraFilter`, `AcesFilmicToneMappingFilter`, `HableFilmicToneMappingFilter`, `HejlBurgessToneMappingFilter`, `LogarithmicToneMappingFilter`, `DragoFilter` (Тональная компрессия); `GammaFilter`, `VibranceFilter` (Яркость и цвет, пакет 3a); `EqualizeFilter`, `EqualizeHistogramFilter`, `EqualizeHistogramHSVFilter`, `EqualizeHistogramPixelationFilter` (Гистограммы); `ClaheFilter`, `EqualizeHistogramAdaptiveFilter` (CLAHE); `AmatorkaFilter`, `KodakFilter`, `BleachBypassFilter`, `CandlelightFilter`, `CelluloidFilter`, `CoffeeFilter`, `DropBluesFilter`, `EdgyAmberFilter`, `FallColorsFilter`, `FilmStock50Filter`, `FoggyNightFilter`, `GoldenForestFilter` (LUT).

Среди проверенных по эталону расхождений нет; среди 27 приближений расходятся 25 фильтров (список в разделе 10; ещё 2 фильтра не сняты, см. там же). `GaussianBlurFilter` и `SaturationFilter` исправлены 2026-10-13 (нативный Aire прочитан в публичном репозитории awxkee/aire и libblur, раздел 10).

Перенесено по формуле и сверено с эталоном в этом заходе: `GlassHexTiles`, `GlassRectTiles`, `GlassTriangleTiles`, `LogarithmicSpiral`, `SpiralDroste` (Искажения) и `GradientMap` (Глитч и CRT).

Итого: 112 зарегистрировано: 85 проверено по эталону, 0 перенесено по формуле, 27 приближений, 45 не перенесено (раздел 8).

## 8. Не перенесено

Имя в скобках — класс Android.

- **Тональная компрессия (4):** `AcesHill` (Aire, точные матрицы не воспроизводятся надёжно по памяти); `Retinex`, `DynamicContrast`, `LocalContrastEnhancement` (G'MIC, CeCILL-C, нативный код). Шесть операторов перенесены по исходникам Aire и совпали с эталоном (см. раздел 9, решения 1 и 15).
- **LUT (3):** `Lookup`: Kotlin создаёт `GPUImageLookupFilter(value)` без второй текстуры, поведение без таблицы не восстанавливается по коду. `LUT512x512` и `CubeLut`: в Kotlin только разбор параметров и вызов `Trickle.applyLut` / `Trickle.applyCubeLut`, а Trickle — нативная библиотека (`libtrickle.so`). Формула `applyLut` найдена 2026-10-13 в публичном репозитории T8RIN/Trickle (решение 14) и используется 12 пресетами; сам `LUT512x512` (таблица от пользователя) остаётся незарегистрированным, а для `CubeLut` формула `applyCubeLutImpl` не разбиралась; вид параметра «файл» не добавлен, потому что без фильтра он не используется. Таблицы 12 пресетов добавлены в `Resources/LUT`. **Отложено (2026-10-11) по решению пользователя.** Вернуться, когда появится вид параметра «файл».
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

1. **Тональная компрессия — гибрид.** Шесть операторов (ACES Narkowicz, Hable, Hejl–Burgess, логарифмический, Uchimura, Drago) перенесены как приближения по опубликованным формулам, а не по Aire. ACES Hill не перенесён. Три G'MIC-фильтра не переносятся. Drago: отображение `threshold` на максимум яркости не сверено с Android. Заменено 2026-10-13: все шесть операторов (без ACES Hill) считаются по исходникам Aire (решение 15).
2. **LUT — таблицы в ресурсах пакета.** 12 `lookup_*.webp` (512 × 512) скопированы из Android `core/resources` в `Sources/ImageToolboxKit/Resources/LUT` и подключены в `Package.swift`. Декодирование через ImageIO при каждом применении, без кэша. `CubeLut` и вид параметра «файл» откладываются. С 2026-10-13 пресеты считаются по формуле Trickle на CPU (решение 14), `CIColorCube` остался только у `CubeLutFilter`.
3. **Приближения принимаются** для этапов 1–2 со статусом «приближение». Пункт «эталонный набор» остаётся невыполненным: сверка с Android по пикселям нужна отдельно.
4. **Движок.** Hue и WhiteBalance считаются на `.cpu` по формулам шейдеров GPUImage (решение 12). HighlightsAndShadows оставлен на `.coreImage` (Saturation с 2026-10-13 на `.cpu`, решение 13, Gamma и Vibrance с 2026-10-13 на `.cpu`, решение 15): ближайший `CIFilter` допустим, если фильтр помечен приближением. Exposure тоже на `.coreImage` (`CIColorMatrix` с множителем 2^EV совпадает с эталоном точно).

Решения 2026-10-11 (пакет A и пакет B):

5. **Формулы из AAR, а не из памяти.** Исходники GPUImage, Jh Labs и матрица Aire в репозитории отсутствуют, но их байткод лежит в AAR зависимостей, которые собирает Android. Шейдеры GPUImage (`tr` по `.class`) и методы `javap -c` дали: Solarize, Posterize, Sharpen, Vignette, Luminance, ColorInvert, ColorMatrix4x4 (GL, `transpose=false`), `SimpleSolarize` (`transferFunction`, JhLabs), Hue, WhiteBalance (вместе с `setHue`, `setTemperature` и `setTint`), SphereRefraction, GlassSphere и ZoomBlur. Матрица сепии `ColorMatrices.SEPIA` взята из `aire-0.18.1.aar`. Это код, который исполняется на Android, в репозиторий он не копируется.
6. **Aire записывает результат усечением.** Сепия: `floor` даёт 12279 точных совпадений из 12288 значений, округление 5866 расхождений. Поэтому `SepiaFilter` и `ColorMatrix3x3Filter` считают на CPU с усечением.
7. **`SolarizeFilter` и `PosterizeFilter` исправлены по шейдеру.** Прежняя версия расходилась с эталоном: Solarize среднее 67.8 и максимум 255, Posterize 25.2 и 51. Solarize инвертирует пиксели, у которых яркость (веса 0.2125, 0.7154, 0.0721) не больше порога, Posterize считает `floor(c · L + 0.5) / L`. Оба теперь совпадают с эталоном точно.
8. **`SimpleSolarizeFilter` перенесён по Java-формуле JhLabs.** Формула `2 (v − 0.5)` при `v > 0.5`, иначе `2 (0.5 − v)`, во Float, с усечением `(int)(f · 255)`. Округление округлением давало 2048 расхождений, а float32 с усечением совпадает точно. Обработка в JhLabs нативная (`libjhlabs.so`), поэтому формула проверена только эталоном.
9. **`ColorMatrix3x3Filter` через Aire.** Порядок операций и усечение подтверждены эталоном сепии и нестандартной матрицей. На нестандартной матрице остаются 236 из 12288 значений на 1 уровень (среднее 0.019). Причину не установлено; вероятно, Aire считает не так, как float32 в порядке `m0 r + m1 g + m2 b`. В допуске, записано числами.
10. **Вид параметра «матрица».** `FilterParameter.Kind.matrix(size:defaultValue:)`, значение `FilterValue.matrix`. Без диапазона, как на Android (текстовое поле через запятую). Ячейка, которую не удалось прочитать как число, получает значение по умолчанию, как на Android. Экран: сетка полей N × N, применение по Return.
11. **LUT-файлы и `Lookup` не переносятся** (раздел 8): нет вида параметра «файл» и таблицы у `Lookup`. Отложено (2026-10-11) по решению пользователя.
12. **Шейдеры GPUImage вместо CoreImage и приближений.** `HueFilter` — поворот в YIQ, как `HUE_FRAGMENT_SHADER`, угол `fmod(градусы, 360) · π / 180` во float32 (метод `setHue`). `WhiteBalanceFilter` — `WHITE_BALANCE_FRAGMENT_SHADER`; температура и тон переводятся как в `setTemperature` (0.00006 · (T − 5000) при T ≥ 5000, иначе 0.0004 · (T − 5000)) и `setTint` (тон / 100). GLSL-матрицы `mat3` заданы по столбцам, это учтено в коэффициентах. `SphereRefractionFilter` и `GlassSphereRefractionFilter` — `SPHERE_FRAGMENT_SHADER` и `GlassSphere`: вне круга результат чёрный (шейдер умножает на `step`), выборка билинейная с краем. `ZoomBlurFilter` — `ZOOM_BLUR_FRAGMENT_SHADER`: девять отсчётов, шаг 0.01 · (центр − пиксель) · size, веса 0.18, 0.15, 0.12, 0.09, 0.05. Эталоны после этого совпали; до переписывания расхождения записаны в разделе 10.
13. **`SaturationFilter` и `GaussianBlurFilter` перенесены по исходникам Aire (2026-10-13).** Исходники нашлись в публичном репозитории `awxkee/aire` (Rust, `aire-filters/src/palette.rs`, `blur.rs`), версия Aire в `libs.versions.toml` — 0.18.1; по `libaire_filters.so` из AAR подтверждены `colorutils-rs-0.7.5` и libblur (путь `fast-gaussian-blur`), исходник libblur взят с crates.io (0.19.4). Параметры по умолчанию Android проверены по Kotlin: Saturation `2f to true`, GaussianBlur `25f, 10f, Reflect101`, ядро `2·25+1 = 51`, `GaussianPreciseLevel.INTEGRAL` (значение 1 = `ConvolutionMode::FixedPoint`).
    - **Saturation.** Aire переводит sRGB в линейный RGB (точная формула, не LUT) и в Oklab, умножает `a` и `b` на силу, возвращается в линейный RGB, при tonemap применяет ACES Hill (`aces_hill`: матрицы 0.59719 и 1.60475, рациональная кривая), обрезает до 0...1 и кодирует в sRGB. Было: `CIColorControls` (яркостная насыщенность, флаг tonemap игнорировался), расхождение 35.5 и 111. Остаточное расхождение 0.35 (2 уровня) давало округление при записи в байт: Aire отбрасывает дробную часть. С усечением: среднее 0.035, максимум 1. Без tonemap ветка `else` в Aire отличается только пропуском ACES, она реализована тем же кодом.
    - **GaussianBlur.** Ядро libblur — значения плотности `exp(-0.5 (x/σ)²)` в целых точках, нормированные на сумму 1, а не интеграл по пикселю (прежняя версия). Кроме того, у libblur нестандартные границы. Строки при ядре от 29 собираются через `write_arena_row`, и справа от строки отражённые пиксели записаны в обратном порядке (`row.chunks_exact_mut(CN).rev()`); при ядре до 28 строки идут через `binter` с обычными краями. Столбцы при ядре до 61 считаются скользящим буфером (`filter_1d_approx_sliding_buffer`), и над первой строкой стоит копия строки 0 (предзагрузка верхнего края) независимо от режима; при ядре больше 61 столбцы идут через `make_arena_columns` с обычными краями. Левый и нижний края ведут себя по режиму. Расхождение было 1.63 и 19, теперь 0.026 и 1. Эталон есть только для ядра 51 (оба эффекта сразу); для ядер меньше 29 и больше 61 поведение взято по исходнику libblur 0.19.4 и на эталонах не проверялось, это допущение. Многопоточный путь libblur (плитки по высоте) на 64x64 не задействован; для больших изображений на устройстве края плиток считаются штатно, а верхний край картинки всё равно копируется.

14. **Пакет 2: LUT, Contrast, Uchimura, Unsharp, Levels, Twirl (2026-10-13).** Все 17 фильтров теперь совпадают с эталоном; причина везде найдена чтением исходника, не подбором.
    - **12 LUT-пресетов.** Trickle 1.9.3 (github.com/T8RIN/Trickle, тег 1.9.3, `trickle/src/main/cpp/ProcessingFilters.cpp`, `applyLutImpl`): интерполяции нет. Каждый канал делится на 4 нацело (`r`, `g`, `b` в 0...63), запись берётся в `x = (b % 8) * 64 + r`, `y = (b / 8) * 64 + g`, результат `round(c·4 + intensity (lut − c·4))`, где `c·4` — канал, округлённый вниз до кратного 4. Прежняя версия строила куб 64 × 64 × 64 и применяла `CIColorCube` (трилинейная интерполяция по полным 8 битам): отсюда 1.1...2.5 среднего и до 14 максимума. Теперь `LUT512x512Filter` хранит саму картинку 512 × 512 и считает на CPU (`engine: .cpu`), `LUTTable` оставлен только для `CubeLutFilter`. Android загружает таблицу `loadBitmap(512)` и `scale(512, 512)` (без изменения размера), байты webp в iOS декодируются ImageIO в те же пиксели: таблицы совпали с эталонами точно (среднее 0, наибольшее 0), отличий декодера нет.
    - **ContrastFilter.** Aire 0.18.1, `color/Adjustments.cpp`, `aire::adjustment(gain, bias 0)`: `gain · (c/255 − 0.5) + 0.5` во Float, `· 255`, в байт усечением. Было `CIColorMatrix` с округлением: 0.667 и 1. Теперь точно. Побочный эффект усечения: `gain = 1` не тождество (на уровне 51 получается 50), тесты `contrastOneIsIdentity` и `order` скорректированы под Aire.
    - **UchimuraFilter.** Формула и константы были верны (`color/tone/UchimuraToneMapper.hpp`); расхождение давало округление байта. `color/ConvolveToneMapper.cpp` записывает `std::clamp(... · 255)` в `uint8_t`, то есть усечение. С усечением: среднее 0.177, наибольшее 1 (остаток — SIMD-приближения степени и экспоненты Highway в Aire, на CPU Swift не воспроизводится). `ToneColour.apply` получил параметр режима округления; остальные операторы по-прежнему округляют (их расхождения другие).
    - **UnsharpFilter.** Aire 0.18.1, `jni/Base.cpp` `unsharpImpl`: `gaussBlurU8` с ядром 5 и sigma 4 (`algo/MathUtils.hpp` `compute1DGaussianKernel`, середина `ceil(5)/2 = 2`), `base/Convolve1D.cpp`: сначала строки, потом столбцы, край повторяет крайний пиксель, после каждого прохода округление (`Round`). Затем `base/Sharpness.cpp` `applyUnsharp`: `c − (c − blur) · intensity` и усечение. Знак минус — в самом Aire (фактически смягчение), перенесено как есть. Прежняя версия: `CIUnsharpMask` с радиусом 2.5. Теперь точно, `engine: .cpu`.
    - **LevelsFilter.** Jh Labs 8.1.0 (T8RIN/ImageToolboxLibs, тег 8.1.0, `libs/jhlabs/src/main/rust/jhlabs/src/lib.rs`, ветка `"LevelsFilter"` и функция `transfer`): таблица на 256 значений, `lowOut + (highOut − lowOut) · (v − low) / (high − low)` во Float, `255 · f` усекается до целого и ограничивается 0...255; позиция не ограничивается до обрезки. Было: округление и ограничение позиции. Теперь точно. Java-класс `LevelsFilter` в Jh Labs пустой, всё считает Rust.
    - **TwirlFilter.** Та же `lib.rs`, `transform_filter`, ветка `"TwirlFilter"`, `bilinear`, `sample`: центр `centre · размер` в пикселях (координаты целые, без сдвига на 0.5), радиус `radius · max(w, h) / 2` во Float, `distance > radius` — пиксель без изменений, иначе угол `angle · (radius − distance) / radius`; билинейная выборка во Float с усечением, край `CLAMP`. Прежняя версия брала центры пикселей (+0.5) и `DistortionSampling.warp` с округлением. Теперь точно.
    - **Источники.** Aire — `awxkee/aire`, master; наличие `unsharpImpl`, `uchimura`, `gaussBlurU8` в `libaire.so` из `aire-0.18.1.aar` подтверждено `strings`. Совпадение с эталоном — окончательная проверка.

15. **Пакет 3a: цвет, тональная компрессия, гистограммы (2026-10-13).** 13 фильтров совпали с эталоном; везде причину нашло чтение исходников, подбора не было. Общее для Aire: он работает с сохранёнными (premultiplied) байтами `Bitmap`, поэтому iOS-версии не снимают и не накладывают альфу, а запись в байт идёт усечением. Источники Aire — `awxkee/aire` (master, апрель 2026), Rust-зависимости взяты с crates.io по версиям из `libaire_filters.so` из `aire-0.18.1.aar`.
    - **Gamma.** Aire 0.18.1, `jni/Base.cpp`, `gammaImpl`: таблица `uint8(clamp(powf(i, gamma), 0, 255))`, где `i` — сам байт 0...255, а не доля. Поэтому `gamma = 1` тождество, 1.5 даёт почти белую картинку (все значения от 41 дают 255), 0.5 тёмную. Прежняя версия: `CIGammaAdjust` по доле 0...1 (140.26 и 237). Значение по умолчанию реестра iOS (1) и Android (1.5) по-прежнему различаются; реестр не менялся.
    - **Vibrance.** Aire 0.18.1, `base/Vibrance.cpp`: не насыщенность, а сдвиг яркости `boost = trunc(clamp((max - (R+G+B)/3) · amount, -255, 255))` (среднее целочисленное), прибавляется ко всем трём каналам. Прежняя версия: `CIVibrance` (104.93 и 255).
    - **Тональная компрессия (ACES, Hable, Hejl–Burgess, логарифмический, Drago).** Aire 0.18.1, `color/ConvolveToneMapper.cpp` и `color/tone/*ToneMapper.hpp`. `exposure` у всех операторов — множитель линейного значения (прежняя версия умножала на `2^exposure`); Hable без нормировки на белую точку 11.2 и без множителя 2 (прежняя версия добавляла и то и другое); Hejl–Burgess после кривой возводит в 2.4 и затем общий путь снова кодирует в sRGB; логарифмический и Drago — по яркости 0.299 / 0.587 / 0.114 с общим масштабом для каналов (прежняя версия обрабатывала каналы по отдельности); Drago `threshold` — максимум яркости SDR `maxLd` в формуле Drago с `Lwa = 1` и bias 0.85, а не `threshold / 250`.
      - **Деление на 255 неточное.** Highway `ApproximateReciprocal` на arm64 — NEON `FRECPE`: `255 · rcp(255)` = 0.99998 (`rcp(255)` = 0.003921509), так же `1/12.92` (0.07739258) и `1/1.055` (0.9472656) в `SRGBToLinear` (`eotf-inl.h`), порог линейного участка там 0.045. Оценка определена спецификацией ARM, её воспроизводит `NEONEmulation.reciprocalEstimate`. С точным 1/255 среднее у логарифмического оператора 0.0017, максимум 1, с оценкой 0.
      - **SIMD-блоки и скалярный хвост различаются.** Aire обрабатывает `4 · ((width - 1) / 4)` первых пикселей строки блоками, остальные 1...4 скалярно. Hejl–Burgess: смещение 0.0004 в блоках и 0.004 в хвосте (разница до 6 уровней в последних четырёх пикселях строки); Drago: максимум `maxLd` в блоках и `maxLd · exposure` в хвосте, хвост возвращается без изменений при масштабе ровно 1; логарифмический: в хвосте при нулевой яркости пиксель не меняется. Оба пути воспроизведены (`AireToneOperator.vector` и `tail`).
      - **Логарифм и степень SIMD-кода** (многочлен `Lognf`, Sleef `Exp` и `LogFast`) отличаются от libm на единицы последнего разряда `Float`; проверено, что с точными функциями байты те же.
      - Uchimura оставлен на прежнем коде (проверен в пакете 2), `ToneColour.apply` остался только у него; он по-прежнему снимает premultiplied, а Aire — нет (на непрозрачном эталоне не видно).
    - **EqualizeFilter (Jh Labs).** T8RIN/ImageToolboxLibs 8.1.0, `lib.rs`, функция `equalize`: по каналу таблица `round(накопленное · 255 / N)` во `Float`, минимум не вычитается. Однотонная картинка поэтому становится белой. Прежняя версия вычитала минимум (43.67 и 127).
    - **EqualizeHistogram, EqualizeHistogramAdaptive, Clahe.** Aire `hists.rs` вызывает крейт `histogram_equalization` 0.2.4 (`hist_equal_yuv_impl.rs`, `clahe_yuv_impl.rs`): картинка переводится в YCgCo (крейт `yuv` 0.8.6, `rgb_to_ycgco.rs` и `ycgco_to_rgb_alpha.rs`, целочисленно с 13 битами точности, полный диапазон, округление вниз при ровно половине), выравнивается только яркость Y, Cg и Co остаются. Прежняя версия выравнивала R, G и B по отдельности. Таблица корзины: `round(255 (cdf - cdfMin) / (N - cdfMin))` в `Double`, `cdfMin` — минимум по всем 256 корзинам, то есть число пикселей с Y = 0. Адаптивные варианты: плитки `width / grid` на `height / grid`, последняя плитка забирает остаток, билинейная интерполяция четырёх таблиц во `Float` с усечением до байта.
      - **CLAHE у Aire обнуляет плитки при малом пороге.** `clip_hist_clahe`: предел `trunc(threshold · w · h / 256)`, в `excess` складывается весь счёт корзины, превысившей предел (а не излишек), а срезанные корзины получают предел. При `threshold` 0.5 и плитке 8 на 8 предел 0, все корзины нули, таблица тоже нули, и яркость Y становится 0: результат эталона почти чёрный, цвет остаётся только из Cg и Co. На настоящих фото плитки крупнее (при 4000 на 3000 и сетке 8 на 8 предел около 360), картинка не чернеет, но обрезка всё равно не та, что в классическом CLAHE. Это поведение Android, оно перенесено как есть.
      - **`NaN` в Rust.** Если все пиксели плитки в корзине 0 (`cdfMin = N`), деление `0 · inf` даёт `NaN`, а `f64::min` отдаёт верхнюю границу, поэтому таблица целиком равна 255. Ветка не проверена эталоном (эталон не содержит чёрных плиток), перенесена по правилу Rust.
      - **Сетка больше картинки.** В Rust размер плитки становится нулевым и деление на него падает (паника в JNI); в iOS размер плитки не меньше одного пикселя.
    - **EqualizeHistogramHSV.** `hist_equal_impl.rs` и `colorutils-rs` 0.7.5: H в целых градусах, S и V целые в `0...bins-1`, выравнивается гистограмма V, H и S остаются. Первые 56 пикселей строки шириной 64 (блоки по 16 и по 8, `while cx + 16 < width`, `while cx + 8 < width`) идут NEON-кодом (`neon/colors.rs`, `neon/image_to_hsv.rs`, `neon/hsv_to_image.rs`), остальные скалярным (`hsv.rs`). NEON: `FRECPE` вместо деления в H и S, `vfmodq_f32` из erydanos 0.2 (`a - trunc(a · (1/b)) · b`), округление `vcvtaq` вместо усечения при переводе в целое и обратно. Скалярный путь усекает H и результат. Без NEON-части расхождение 0.52 и 5 (хвост строки уже точный), с ней 0. Пересчёт цвета выполняется дважды (гистограмма, затем замена V), поэтому лишней памяти не нужно.
    - **EqualizeHistogramPixelation.** `aire-filters/src/equalize_hist.rs`: плитки `width / grid`, в каждой скалярный HSV (`hsv.rs`, H и S во `Float`) и гистограмма V из 101 корзины (`round(V · 100)`), новая V — `round(100 (cdf - cdfMin) / (N - cdfMin)) / 100`, обратный перевод усекает. На сетке 50 для 64x64 плитка из одного пикселя, поэтому V всегда 1 (при V = 0 тоже: `NaN` в Rust даёт верхнюю границу). Прежняя версия: поканальное выравнивание в плитках без переноса H и S (75.85 и 255).
    - **Источники.** Крейты взяты с crates.io: `histogram_equalization` 0.2.4, `colorutils-rs` 0.7.5, `yuv` 0.8.6, `erydanos` 0.2.18 (версия из `Cargo.lock` aire-filters; `libaire_filters.so` содержит пути именно этих версий, кроме erydanos, у которого строк-путей нет). Совпадение с эталоном — окончательная проверка: 13 фильтров дают среднее 0 и наибольшее 0.

16. **Пакет 3b: морфология и размытия (2026-10-13).** 18 фильтров и случай `GaussianBlurFilter_r40` совпали с эталоном побитово (среднее 0, наибольшее 0). Причину везде нашло чтение исходников, подбора нет. Источники: Aire 0.18.1 (`awxkee/aire`, master; `aire-filters/src/blur.rs`, `morph.rs`, C++ в `aire/src/main/cpp`), `fast_morphology` 0.3.1 и libblur 0.19.4 (оба с crates.io), Trickle 1.9.3 (`trickle/src/main/cpp/Utils.cpp`). Версию libblur по `.so` точно не определить (в строках путь локальной копии `RustroverProjects/fast-gaussian-blur`), но все 48 путей `src/*.rs` из `libaire_filters.so` есть в 0.19.4, и эталоны сошлись побитово везде, где их сняли. Целочисленные части модели (rdm-обработчики) подтверждены тем, что эмулятор arm64 выполняет путь с расширением RDM: иначе не появились бы дефекты обработчика по три строки (ниже).
    - **Рамка с дефектом (`AireArena`).** `fast_morphology` (`arena.rs`) и libblur (`filter1d/arena.rs`, `make_arena`) строят рамку четырьмя полосами: верхняя и нижняя на всю ширину, левая и правая между ними. Индекс источника считает `reflect_index_101(i, n) = (n - 1) - i mod (n - 1)` (у `Reflect` `n - i mod n - 1`). Вне картинки это обычное отражение, но для индексов внутри картинки функция даёт зеркальный индекс. Поэтому середина верхней и нижней полос зеркальна по горизонтали, середина левой и правой по вертикали, а индекс 0 в полосы не попадает. Прежние версии брали обычное отражение; отсюда ошибки до 220 уровней у границ в морфологии (на дилатации 16.2 среднего). `Clamp` и `Wrap` дефекта не имеют. Рамкой пользуются морфология, боке, `BilaterialBlurFilter` и `MotionBlurFilter`.
    - **Морфология.** Ядра: `MorphKernels.circle(size)` строит `ConvolveKernels.circle`: точки, чьё расстояние до `(size / 2, size / 2)` (целая половина) не больше `Float(size) / 3` (для 25 радиус 8.33, 221 точка; прежняя версия брала диск радиуса `size / 2`), `box` — все точки; якорь `size / 2`, отступ рамки `size / 2`. Режим выбирает `Trickle.checkHasAlpha` (`ScanAlpha.cpp`): если у всех пикселей альфа 255, считается RGB и альфа результата 255, иначе RGBA и альфа обрабатывается как обычный канал, в том числе в градиенте, top-hat и black-hat (прежняя версия сохраняла альфу). Градиент, top-hat, black-hat — насыщающее вычитание байтов (`morph_gradient`); открытие и закрытие — две отдельные операции, у каждой своя рамка. Скорость: для каждой строки рамки один раз строится пирамида окон `M(j)[x] = op(M(j-1)[x], M(j-1)[x + 2^(j-1)])`, отрезок ядра из `n` точек берётся двумя окнами; цена на пиксель зависит от числа строк ядра, не точек, байты обрабатываются по 16 (`SIMD16`), строки параллельно. Прежний код был линейным по длине ядра, но с аллокацией на каждую строку и проход по столбцам через копии.
    - **Боке.** `Aire.getBokehKernel(size, sides)` (`algo/EigenUtils.h`, `getBokehEffect`): всё во `Float`, центр `size / 2`, радиус `0.85 · min(cx, cy)`, вершины `Int(cx + r cos(2π i / n))`, линии Брезенхэма между соседними вершинами, заливка по четырём соседям от центра. Затем дилатация этим ядром `size x size` (для 6 ядро чётное, якорь 3). Прежняя версия брала вписанный многоугольник по апофеме. Android бросает исключение при размере или числе сторон меньше 3; здесь ядро строится и для них.
    - **Box, tent, stack (libblur `box_filter/box_blur.rs`, `stackblur/`).** Край повторяет крайний пиксель (clamp) вдоль обеих осей, на каждом проходе `round(сумма · (1 / ядро))` во `Float` (стек: делитель `(r + 1)^2`), строки, затем столбцы; пути NEON (Q0.31) на эталоне дают то же, что `Float`. Прежняя версия отражала край (`reflect101`) и для stack/tent брала свою трактовку. Tent: `create_box_gauss(sigma, 2)` (все операции во `Float`) даёт два окна, для sigma 15 это 19 и 19, то есть два прохода box с ядром 39; sigma — `roundToNearestOdd(value)`. Stack — треугольное ядро `radius + 1 - |k|`. Всё считается скользящими целыми суммами за время, не зависящее от радиуса.
    - **Медиана (libblur `median_blur.rs`).** Aire передаёт радиус `2 · round(value) + 1` (для 10 это 21, окно по строкам 43). Гистограмма окна ведётся как в libblur: по строкам `y - radius...y + radius` без отражения (на краю окно короче); по столбцам для `x = 0` в неё входят столбцы `0..<radius`, затем при сдвиге добавляется `x + radius` и убирается `x - radius`, поэтому столбец `radius` в гистограмму не попадает, а при `x = 2 radius` убирается (счётчики уходят в минус); «медиана» — первый бин, где накопленная сумма доходит до `n / 2` (целое деление), то есть для нечётного `n` на единицу ниже середины. Всё перенесено как есть. Время O(пикселей · радиус).
    - **BilaterialBlur: сигмы переставлены.** `Aire.bilateralBlur(rangeSigma, spatialSigma)` передаёт их в JNI позиционно как `(kernelSize, spatial, range)`, и в libblur `spatial_sigma` (пиксели) получает `rangeSigma` фильтра (3), а `range_sigma` (в долях 1: разница каналов `Δ / 255`) — `spatialSigma` (10). Цветовой вес `exp(-Δ^2 / 200)` почти не меняется, фильтр практически гауссов с sigma 3 пикселя. Прежняя версия считала по шкале 0...255 и с общим весом по RGB. Каналы R, G, B, A независимы, веса — таблицы `Float` (`exp` от `-(dx^2 + dy^2) · 1 / (2 σ^2)` и от `-((p - q) / 255)^2 · 1 / (2 σ^2)`), сумма по окну идёт строка за строкой слева направо с `fma` (NEON), `round(сумма / вес)`, вес 0 заменяется на 1. Порядок суммирования важен для побитового совпадения, поэтому окно не переупорядочивается. Рамка `AireArena`. NEON-код libblur для ширин с остатком (`ширина · 4` не кратно 16 байтам) считает 1...3 последних пикселя строки по окну с левого края строки (индекс `x` в остатке отсчитан от нуля), скалярный остаток без `fma`: перенесено по исходнику, эталон (ширина 64) этого не видит.
    - **FastBilaterialBlur (libblur `fast_bilateral_filter.rs`).** Билатеральная сетка на каждый канал: масштабы `spatial_sigma_scale` и `range_sigma_scale`, ячейки (x, y, яркость) с суммой и числом, три прохода гауссовым ядром `gaussian_kernel_1d(kernel, sqrt(σs^2 + σr^2))` (со сдвигом правой половины на один отсчёт, как в libblur), выборка трилинейно, деление суммы на число. Порядок операций `Float` сохранён. Сигмы идут в libblur как в Kotlin (здесь перестановки нет).
    - **MotionBlur (libblur `motion_blur.rs`).** Ядро `size x size` с линией Брезенхэма между точками `(⌈size/2 + size cos a⌉, ⌈size/2 + size sin a⌉)` и симметричной (`size - 1 - x`), в ядро входят пиксели линии внутри `0..<size`, вес `1 / n`. Свёртка `filter_2d` для байтов идёт в фиксированной точке: вес `round(w · 32767)` как `i16`, результат `(сумма + 2^14) >> 15`. Края — рамка `AireArena` (с дефектом). Размер ядра `roundToNearestOdd(size)`.
    - **Tilt-shift (Aire `shift/TiltShift.cpp`).** Картинка размывается `gaussBlurU8(radius, sigma)`: ядро `compute1DGaussianKernel(radius, sigma)` длиной `radius` (а не `2 radius + 1`), центр `radius / 2`; строки, затем столбцы, `Round` (до чётного) после каждого. Дефект строкового прохода (`base/Convolve1D.cpp`, Highway): для ядер длиной не 3, 5, 7 и 9 блоки по четыре отсчёта читают четыре подряд идущих пикселя от `clamp(x + r)`, и слева от картинки вместо повторов пикселя 0 стоят пиксели 0, 1, 2, 3. Смешивание: доля `clamp((расстояние / минимальное)^3, 0, 1)`, цвета делятся на 255 и смешиваются как `x · (1 - a) + y · a` (`a` — доля, умноженная на альфу размытого), байт получается усечением, альфа берётся из исходной картинки. Радиальный: расстояние от якоря `Int(w · anchorX)`, `Int(h · anchorY)`, минимальное `sqrt(w^2 + h^2) · radius`. Линейный: точка поворачивается на угол вокруг якоря (в целых), расстояние берётся по x или по y в зависимости от `fmod(angle + π, 2π) - π` относительно ±π/4, минимальное — от размера повёрнутого прямоугольника. Прежняя версия брала своё ядро (интеграл по пикселю, `2r + 1`), маску и ширину перехода.
    - **FastBlur (Trickle `Utils.cpp`, `fastBlurImpl`).** `Bitmap.createScaledBitmap(.., filter = true)` до `round(w · scale)`, box-размытие радиусом `radius` по RGB (скользящая сумма, целое деление с усечением, альфа результата 255), `createScaledBitmap` обратно. Масштабирование Android — билинейная выборка Skia с четырьмя битами дробной части весов (`SkBitmapProcState`, `Filter_32_opaque`): центр пикселя результата переводится в координаты источника и сдвигается на полпикселя, веса соседних пикселей по 1/16 с усечением дроби, сумма делится на 256 с усечением. Эталон (масштаб 0.5: уменьшение вдвое и увеличение вдвое) подтверждает усечение (округление давало 0.135 среднего), но не позволяет отличить эту модель от других при дробных масштабах: для остальных масштабов выборка воспроизведена по устройству Skia и на эталоне не проверена. Прежняя версия брала ближайшего соседа. Результат всегда исходного размера (у Android `Int(w / scale)`).
    - **GaussianBlur ядро 81 (радиус 40).** Причин две. Столбцы при ядре больше 61: `create_brows` берёт строки верхней подушки по индексу `pad - k - 1` и нижней по `k - pad - 1` (в обоих случаях без поправки на строку `y`, поэтому они ведут к другим строкам, чем задумано), а обработчик по три строки (`filter_column_symm_neon_u8_i32_rdm_x3`) оставляет последние `высота mod 3` строк одиночному обработчику, у которого номер строки отсчитан от нуля: эти строки повторяют строки `0..<высота mod 3` результата (для 64 строк последняя копия строки 0). И арифметика обработчиков: на arm64 с RDM веса `i16` (`Float`-ядро · 2^15, усечение), слагаемое каждого отсчёта `((a + b) · w + 256) >> 9` (`vqrdmulhq_s16` над значениями, сдвинутыми на 6), результат `(сумма + 32) >> 6`; последние 4 байта строки идут скалярным путём с `(сумма · w + 2^14) >> 15`. Это же даёт для ядра 51 (радиус 25) побитовое совпадение вместо 0.026 и 1, ядро 11 (радиус 5) остаётся на `Float`-модели (строки обрабатывает другой код, `binter`) и тоже совпадает. Новый код: `LibblurGaussian` (ядра от 29 отсчётов).
    - **Поведение Android, которое выглядит ошибкой и перенесено как есть (кандидаты на решение по продукту).** Зеркальная середина полос рамки (морфология, боке, билатеральный, motion); медиана libblur (лишний выпавший столбец, нижняя «медиана», радиус `2 · value + 1`); у `BilaterialBlur` перестановка сигм; хвост строки NEON-билатерального фильтра на ширинах не кратных 4; у гауссова размытия с ядром больше 61 повторение первых строк внизу и смещённые строки подушек; у ядра от 29 справа обратный порядок отражённых пикселей; у `gaussBlurU8` (tilt-shift) чтение подряд идущих пикселей слева; у tilt-shift при нулевом радиусе зоны фокуса пиксель якоря чёрный (`NaN` в байт); `Trickle.fastBlur` делает картинку непрозрачной (альфа 255), может менять размер и при `radius < 1` возвращает исходную картинку; веса `i16` в rdm-обработчиках переполняются при ядре, где центральный вес не меньше 1 (sigma около 0.5 и меньше при ядре от 29); морфология Android не принимает круг меньше 5 и боке меньше 3 (исключение), в iOS эти значения считаются.
    - **Источники и проверка.** Совпадение с эталоном — окончательная проверка: все 18 фильтров и случай `_r40` дают среднее 0 и наибольшее 0. Python-реплики лежали вне репозитория; побитовое совпадение получено для каждой гипотезы отдельно, остаточное расхождение 1 уровень на двух значениях (последний пиксель столбца) устранило скалярный хвост в столбцах.

Открытые вопросы:

- **Эталоны.** Снято 112 эталонов (раздел 10): 27 с 2026-10-11 и 85 новых 2026-10-13 (приближения, `LevelsFilter_custom` и два дополнительных размера ядра `GaussianBlurFilter`). Проверены 85 фильтров; `GaussianBlurFilter` и `SaturationFilter` закрыты 2026-10-13 (решение 13), ещё 17 фильтров закрыты в пакете 2 (решение 14), ещё 13 в пакете 3a (решение 15), ещё 18 в пакете 3b (решение 16). Эталонов нет у `GrainFilter` и `RandomDitheringFilter` (недетерминированы на Android), а также у 45 не перенесённых фильтров. Расхождения 25 случаев записаны числами и ждут отдельной задачи исправления. Эталоны сняты на эмуляторе arm64 с программным GL (`hw.gpu.enabled=no`), на устройстве с GPU не сверялись.
- **Заголовки параметров.** У `BilaterialBlur` и `FastBilaterialBlur` подпись второго параметра («sigma») в Kotlin управляет `spatialSigma`, а `spatial_sigma` — `rangeSigma`. Значения по умолчанию сохранены, подписи стоит поправить. Это про подписи в UI; в самом Aire сигмы у `BilaterialBlur` ещё и переставлены между Kotlin и libblur (решение 16).
- **TentBlur.** Значение по умолчанию в UI (10) и в Kotlin (15) различаются; взято значение UI.
- **Производительность.** Замер пакета 3b (12 Мп, 4000 на 3000, релизная сборка, M-серия, все ядра): таблица в разделе 10. LUT по-прежнему декодирует таблицу при каждом применении (замер не выполнен).
- **`SimpleSolarizeFilter`** добавлен 2026-10-11 (решение 8), проверен эталоном.
- **Формат шаблонов (F4).** `FilterTemplate` сохраняется в JSON по Swift-структуре; совместимость с Android не проверялась.
- **Блокеры F1–F4** не закрыты: G'MIC, лицензии, OpenCV и формат шаблонов ждут решения пользователя.

## 10. Сверка с эталонами Android (2026-10-11)

Эталоны сняты инструментальным тестом `ReferenceFilterExportTest` (`feature/filters/src/androidTest/java/.../feature/filters/data/model/`). Тест применяет фильтры через `transform` к `reference/ui-sample.png` (64x64, байты совпадают с фикстурой UI-теста). Фильтр берётся с параметрами по умолчанию Android: конструктор без аргументов, а для процедурных фильтров значения из `ProceduralEffect`, для градиента палитра `Spectral`. Всего 112 случаев: 27 с 2026-10-11 (25 фильтров по умолчанию и две нестандартные матрицы `*_custom`; с 2026-10-13 совпадают все 27) и 85 добавленных 2026-10-13: 82 приближения по умолчанию Android, `LevelsFilter_custom` (уровни по умолчанию тождественны входу, тест требует `!sameAs`) и два дополнительных размера ядра `GaussianBlurFilter_r5` и `GaussianBlurFilter_r40`. Пропущены `GrainFilter` и `RandomDitheringFilter`: два прогона на эмуляторе дают разные PNG. Остальные PNG двух прогонов совпали побайтово; 27 прежних эталонов и `input.png` совпали побайтово с зафиксированными в репозитории.

Запуск на эмуляторе `itb37` (Android API 37.0, google_apis, arm64, `hw.gpu.enabled=no`, GL через SwiftShader), JDK 21:

```bash
./gradlew :instrumentation-tests:connectedFossDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.t8rin.imagetoolbox.feature.filters.data.model.ReferenceFilterExportTest -Pandroid.injected.androidTest.leaveApksInstalledAfterRun=true
```

Флаг `leaveApksInstalledAfterRun` нужен: без него AGP удаляет приложение вместе с файлами эталонов. Забор эталонов:

```bash
adb pull /sdcard/Android/data/ru.tech.imageresizershrinker.debug/files/reference/. ios/ImageToolboxKit/Tests/ImageToolboxKitTests/Fixtures/AndroidReference/
```

Сверка: `AndroidReferenceParityTests` (Swift Testing), по каналам RGB. Допуск: среднее отличие не больше 0.25 и наибольшее не больше 1. Расхождение, которое не укладывается в допуск, записывается в тесте через `withKnownIssue` с числами; сейчас таких 25 случаев (из 112).

| Фильтр | Параметры | Среднее | Наибольшее | Статус |
|---|---|---|---|---|
| `SepiaFilter` | по умолчанию | 0.0007 | 1 | проверено (9 значений на 1 уровень) |
| `NegativeFilter` | по умолчанию | 0 | 0 | проверено, точно |
| `BlackAndWhiteFilter` | по умолчанию | 0.0059 | 1 | проверено |
| `SolarizeFilter` | порог 0.5 | 0 | 0 | проверено, точно |
| `PosterizeFilter` | 5 уровней | 0 | 0 | проверено, точно |
| `GaussianBlurFilter` | радиус 25, sigma 10, Reflect101 | 0 | 0 | проверено, точно (до 2026-10-13: 1.63 и 19; после решения 13: 0.026 и 1) |
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

### Сверка приближений (2026-10-13)

Режим только измерения: реализации фильтров не менялись, допуски не менялись. Параметры iOS-фильтра совпадают со значениями по умолчанию Kotlin-класса (проверено по исходникам): отличаются от значений в реестре iOS только `GammaFilter` (Android 1.5, реестр 1) и `TentBlurFilter` (Android 15, реестр 10); в таблице взяты значения Android. У `HighlightsAndShadowsFilter` Android передаёт `GPUImageHighlightShadowWideRangeFilter(0.25, 1)`: в iOS есть только параметр теней, подсветка не задаётся. У `Clustered*DitheringFilter` порог Android (`Trickle.dithering` без `threshold`) не виден, в iOS параметра порога нет. `LevelsFilter_custom`: уровни 0.1, 0.9, 0.2, 0.8. Таблица отсортирована по наибольшему расхождению, затем по среднему.

| Фильтр | Параметры (аргументы Swift, значения по умолчанию Android) | Среднее | Наибольшее | Статус |
|---|---|---|---|---|
| `BayerTwoDitheringFilter` | threshold: 200, grayScale: false | 118.20 | 255 | расхождение |
| `BayerEightDitheringFilter` | threshold: 200, grayScale: false | 114.55 | 255 | расхождение |
| `BayerFourDitheringFilter` | threshold: 200, grayScale: false | 110.57 | 255 | расхождение |
| `StuckiDitheringFilter` | threshold: 200, grayScale: false | 103.82 | 255 | расхождение |
| `SierraLiteDitheringFilter` | threshold: 200, grayScale: false | 103.39 | 255 | расхождение |
| `Clustered8x8DitheringFilter` | grayScale: false | 101.77 | 255 | расхождение |
| `JarvisJudiceNinkeDitheringFilter` | threshold: 200, grayScale: false | 100.29 | 255 | расхождение |
| `SierraDitheringFilter` | threshold: 200, grayScale: false | 98.47 | 255 | расхождение |
| `BurkesDitheringFilter` | threshold: 200, grayScale: false | 93.70 | 255 | расхождение |
| `Clustered4x4DitheringFilter` | grayScale: false | 92.97 | 255 | расхождение |
| `BayerThreeDitheringFilter` | threshold: 200, grayScale: false | 87.03 | 255 | расхождение |
| `Clustered2x2DitheringFilter` | grayScale: false | 85.00 | 255 | расхождение |
| `AtkinsonDitheringFilter` | threshold: 200, grayScale: false | 83.51 | 255 | расхождение |
| `GlitchFilter` | amount: 20, seed: 15, iterations: 9 | 81.18 | 255 | расхождение |
| `TwoRowSierraDitheringFilter` | threshold: 200, grayScale: false | 78.19 | 255 | расхождение |
| `FloydSteinbergDitheringFilter` | threshold: 200, grayScale: false | 73.11 | 255 | расхождение |
| `FalseFloydSteinbergDitheringFilter` | threshold: 200, grayScale: false | 59.48 | 255 | расхождение |
| `LeftToRightDitheringFilter` | threshold: 200, grayScale: false | 8.093 | 255 | расхождение |
| `RippleFilter` | xAmplitude: 5, xWavelength: 16, yAmplitude: 5, yWavelength: 16 | 22.00 | 252 | расхождение |
| `CirclePixelationFilter` | size: 24 | 4.513 | 120 | расхождение |
| `HighlightsAndShadowsFilter` | shadows: 0.25 | 21.75 | 110 | расхождение |
| `FishEyeFilter` | radius: 70, amplitude: 1 | 8.189 | 62 | расхождение |
| `KaleidoscopeFilter` | angle: 0, secondaryAngle: 0, centreX: 0.5, centreY: 0.5, sides: 5, radius: 0 | 8.054 | 41 | расхождение |
| `PinchFilter` | angle: 15, centreX: 0.5, centreY: 0.5, radius: 1, amount: 0.5 | 6.573 | 37 | расхождение |
| `DiamondPixelationFilter` | size: 24 | 0.7078 | 15 | расхождение |
| `BrightnessFilter` | bias: 0.5 | 0.0104 | 1 | проверено |
| `LevelsFilter_custom` | lowInput: 0.1, highInput: 0.9, lowOutput: 0.2, highOutput: 0.8 | 0 | 0 | проверено, точно (до 2026-10-13: 2.198 и 20) |
| `KodakFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 2.472 и 14) |
| `CandlelightFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.793 и 10) |
| `FoggyNightFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.917 и 8) |
| `CelluloidFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.783 и 8) |
| `BleachBypassFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.725 и 7) |
| `EdgyAmberFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.674 и 7) |
| `CoffeeFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.505 и 6) |
| `AmatorkaFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.683 и 5) |
| `FilmStock50Filter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.615 и 5) |
| `GoldenForestFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.149 и 5) |
| `DropBluesFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.478 и 4) |
| `FallColorsFilter` | сила 1 | 0 | 0 | проверено, точно (до 2026-10-13: 1.393 и 4) |
| `UnsharpFilter` | intensity: 0.5 | 0 | 0 | проверено, точно (до 2026-10-13: 0.147 и 4) |
| `TwirlFilter` | angle: 45, centreX: 0.5, centreY: 0.5, radius: 0.5 | 0 | 0 | проверено, точно (до 2026-10-13: 0.1001 и 3) |
| `UchimuraFilter` | scale: 1 | 0.1771 | 1 | проверено (до 2026-10-13: 0.8854 и 1) |
| `ContrastFilter` | gain: 2 | 0 | 0 | проверено, точно (до 2026-10-13: 0.6667 и 1) |
| `ClaheFilter` | threshold: 0.5, gridX: 8, gridY: 8 | 0 | 0 | проверено, точно (до 2026-10-13: 207.23 и 255) |
| `VibranceFilter` | amount: 3 | 0 | 0 | проверено, точно (до 2026-10-13: 104.93 и 255) |
| `EqualizeHistogramPixelationFilter` | gridX: 50, gridY: 50 | 0 | 0 | проверено, точно (до 2026-10-13: 75.85 и 255) |
| `GammaFilter` | power: 1.5 | 0 | 0 | проверено, точно (до 2026-10-13: 140.26 и 237) |
| `EqualizeFilter` | нет параметров | 0 | 0 | проверено, точно (до 2026-10-13: 43.67 и 127) |
| `EqualizeHistogramAdaptiveFilter` | gridX: 3, gridY: 3 | 0 | 0 | проверено, точно (до 2026-10-13: 31.92 и 121) |
| `HableFilmicToneMappingFilter` | exposure: 1 | 0 | 0 | проверено, точно (до 2026-10-13: 68.22 и 92) |
| `EqualizeHistogramHSVFilter` | bins: 128 | 0 | 0 | проверено, точно (до 2026-10-13: 29.96 и 68) |
| `DragoFilter` | scale: 1, whitePoint: 250 | 0 | 0 | проверено, точно (до 2026-10-13: 40.02 и 65) |
| `LogarithmicToneMappingFilter` | exposure: 1 | 0 | 0 | проверено, точно (до 2026-10-13: 36.95 и 62) |
| `AcesFilmicToneMappingFilter` | exposure: 1 | 0 | 0 | проверено, точно (до 2026-10-13: 34.76 и 51) |
| `HejlBurgessToneMappingFilter` | exposure: 1 | 0 | 0 | проверено, точно (до 2026-10-13: 37.37 и 50) |
| `EqualizeHistogramFilter` | нет параметров | 0 | 0 | проверено, точно (до 2026-10-13: 25.02 и 49) |
| `BokehFilter` | size: 6, sides: 6 | 0 | 0 | проверено, точно (до 2026-10-13: 3.359 и 244) |
| `OpeningFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 3.314 и 220) |
| `ClosingFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 3.301 и 216) |
| `MorphologicalGradientFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 29.36 и 204) |
| `DilationFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 16.17 и 204) |
| `ErodeFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 16.10 и 200) |
| `GaussianBlurFilter_r40` | radius: 40, sigma: 15, edge: .reflect101 | 0 | 0 | проверено, точно (до 2026-10-13: 3.396 и 125) |
| `MotionBlurFilter` | size: 25, degrees: 45, edge: .reflect101 | 0 | 0 | проверено, точно (до 2026-10-13: 7.421 и 103) |
| `BilaterialBlurFilter` | radius: 12, spatialSigma: 10, rangeSigma: 3, edge: .reflect101 | 0 | 0 | проверено, точно (до 2026-10-13: 3.247 и 89) |
| `FastBilaterialBlurFilter` | size: 11, spatialSigma: 10, rangeSigma: 3 | 0 | 0 | проверено, точно (до 2026-10-13: 14.09 и 50) |
| `MedianBlurFilter` | radius: 10 | 0 | 0 | проверено, точно (до 2026-10-13: 8.188 и 32) |
| `TentBlurFilter` | size: 15 | 0 | 0 | проверено, точно (до 2026-10-13: 6.094 и 24) |
| `TopHatFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 2.214 и 24) |
| `BlackHatFilter` | size: 25, circle: true | 0 | 0 | проверено, точно (до 2026-10-13: 2.214 и 24) |
| `RadialTiltShiftFilter` | blurRadius: 25, sigma: 10, anchorX: 0.5, anchorY: 0.5, hole: 0.2 | 0 | 0 | проверено, точно (до 2026-10-13: 2.992 и 20) |
| `LinearTiltShiftFilter` | blurRadius: 25, sigma: 10, anchorX: 0.5, anchorY: 0.5, hole: 0.2, degrees: 45 | 0 | 0 | проверено, точно (до 2026-10-13: 1.505 и 20) |
| `NativeStackBlurFilter` | radius: 25 | 0 | 0 | проверено, точно (до 2026-10-13: 2.521 и 18) |
| `FastBlurFilter` | scale: 0.5, radius: 5 | 0 | 0 | проверено, точно (до 2026-10-13: 2.115 и 14) |
| `BoxBlurFilter` | radius: 10 | 0 | 0 | проверено, точно (до 2026-10-13: 0.875 и 11) |
| `SimpleThresholdDitheringFilter` | threshold: 200, grayScale: false | 0 | 0 | проверено, точно |
| `GaussianBlurFilter_r5` | radius: 5, sigma: 2, edge: .reflect101 | 0 | 0 | проверено, точно |
| `ProtanopiaFilter` | нет параметров | 0.0009 | 1 | проверено |
| `DeuteranopiaFilter` | нет параметров | 0.0021 | 1 | проверено |
| `TritanopiaFilter` | нет параметров | 0.0178 | 1 | проверено |
| `AchromatopsiaFilter` | нет параметров | 0 | 0 | проверено, точно |
| `ProtonomalyFilter` | нет параметров | 0.0015 | 1 | проверено |
| `DeutaromalyFilter` | нет параметров | 0.0017 | 1 | проверено |
| `TritonomalyFilter` | нет параметров | 0 | 0 | проверено, точно |
| `AchromatomalyFilter` | нет параметров | 0.0033 | 1 | проверено |

Совпали с эталоном (60 из 85): `BrightnessFilter`, `SimpleThresholdDitheringFilter`, `GaussianBlurFilter_r5`, восемь фильтров дальтонизма (ниже), 17 случаев пакета 2 (12 LUT-пресетов, `ContrastFilter`, `UchimuraFilter`, `UnsharpFilter`, `LevelsFilter_custom`, `TwirlFilter`; решение 14, значения «до» указаны в таблице) и 13 случаев пакета 3a (`GammaFilter`, `VibranceFilter`, пять операторов тональной компрессии, `EqualizeFilter`, пять фильтров гистограмм; решение 15). Первые два фильтра переведены из «приближения» в «проверено по эталону» (`GaussianBlurFilter` уже был проверен на ядре 51), а также 19 случаев пакета 3b (семь фильтров морфологии, `BokehFilter`, `BoxBlurFilter`, `TentBlurFilter`, `NativeStackBlurFilter`, `MedianBlurFilter`, `BilaterialBlurFilter`, `FastBilaterialBlurFilter`, `MotionBlurFilter`, оба tilt-shift, `FastBlurFilter` и `GaussianBlurFilter_r40`; решение 16, значения «до» в таблице).

`GaussianBlurFilter` на других ядрах:
- радиус 5, sigma 2, Reflect101 (ядро 11, меньше 29): среднее 0, наибольшее 0, совпадает точно.
- радиус 40, sigma 15, Reflect101 (ядро 81, больше 61): среднее 0, наибольшее 0 (до 2026-10-13: 3.396 и 125). Допущение решения 13 про края для ядер больше 61 не подтвердилось; настоящая причина — выбор строк подушек в `create_brows`, обработчик по три строки и целая арифметика rdm-обработчиков (решение 16). Это же дало точное совпадение для ядра 51.

Время на 12 Мп (пакет 3b, решение 16). Картинка 4000 на 3000, непрозрачная, сборка `swift build -c release`, Apple Silicon (M-серия), все ядра, одно применение фильтра. Параметры по умолчанию Android, если не сказано иное:

| Фильтр | Параметры | Время, с |
|---|---|---|
| `DilationFilter` | круг 25 | 0.16 |
| `OpeningFilter` | круг 25 | 0.33 |
| `MorphologicalGradientFilter` | круг 25 | 0.32 |
| `TopHatFilter` | квадрат 25 | 0.33 |
| `DilationFilter` | круг 150 | 0.37 |
| `BokehFilter` | размер 40, 6 сторон | 0.21 |
| `BoxBlurFilter` | 10 | 0.04 |
| `GaussianBlurFilter` | радиус 25, sigma 10 | 0.16 |
| `GaussianBlurFilter` | радиус 40, sigma 15 | 0.25 |
| `GaussianBlurFilter` | радиус 5, sigma 2 (`Float`-модель, строки `binter`) | 1.26 |
| `NativeStackBlurFilter` | 25 | 0.05 |
| `NativeStackBlurFilter` | 250 | 0.04 |
| `TentBlurFilter` | 15 | 0.09 |
| `MedianBlurFilter` | 10 | 1.00 |
| `MedianBlurFilter` | 30 | 1.75 |
| `BilaterialBlurFilter` | радиус 12 | 2.19 |
| `BilaterialBlurFilter` | радиус 25 | 9.48 |
| `FastBilaterialBlurFilter` | размер 11 | 0.65 |
| `FastBilaterialBlurFilter` | размер 51 | 0.93 |
| `MotionBlurFilter` | размер 25, 45 градусов | 0.02 |
| `MotionBlurFilter` | размер 201, 45 градусов | 0.24 |
| `RadialTiltShiftFilter` | радиус 25, sigma 10 | 0.16 |
| `LinearTiltShiftFilter` | радиус 25, sigma 10 | 0.18 |
| `FastBlurFilter` | масштаб 0.5, радиус 5 | 0.06 |

Точный билатеральный фильтр считает O(пикселей · ядро^2); ускорить его, не меняя порядок сумм `Float` (от него зависит побитовое совпадение), нельзя, на Android он тоже самый медленный из набора. Остальные фильтры линейны по пикселям (скользящие суммы, пирамида окон, свёртка в фиксированной точке) или по радиусу (медиана).

Наблюдения (не проверялись, только по числам): дизеринг с распространением ошибки, Bayer и Clustered расходятся почти полностью (среднее 59...118 из 255): нативный Trickle в репозитории отсутствует, формулы подобраны по общим схемам.

Фильтры дальтонизма (исправлено 2026-10-13): Protanopia, Deuteranopia, Tritanopia, Achromatopsia, Protonomaly, Deutaromaly, Tritonomaly, Achromatomaly. Было: матрицы Machado 2009 и смеси 50% (путь `CIColorMatrix`), расхождения от 0.50 и 1 (Achromatopsia) до среднего 32.54 и 130 (Protanopia). Причина: Android вызывает `ColorMatrix3x3Filter(ColorMatrices.Assistance.*)` с собственными константами Aire, а iOS подставляла чужие матрицы. У Achromatopsia константы совпадали (0.299, 0.587, 0.114), её 0.50 давало округление в `CIColorMatrix` вместо усечения в Aire. Теперь константы `ColorMatrices.Assistance` взяты из classes.jar артефакта aire-0.18.1.aar (`javap -c`, массивы PROTANOPIA, DEUTARONOPIA, TRITANOPIA, ACHROMATOPSIA, PROTANOMALY, DEUTAROMALY, TRITONOMALY, ACHROMATOMALY) и применяются через `apply3x3` (строка матрицы — выходной канал, транспонирования нет). Значения 0.18.1 совпадают с master Aire. Результат (среднее и наибольшее): Protanopia 0.0009 и 1, Deuteranopia 0.0021 и 1, Tritanopia 0.0178 и 1, Achromatopsia 0 и 0, Protonomaly 0.0015 и 1, Deutaromaly 0.0017 и 1, Tritonomaly 0 и 0, Achromatomaly 0.0033 и 1. Остаток в один уровень на единицах пикселей — разница округления Float.

Границы этой сверки: вход один, 64x64, непрозрачный, без краёв прозрачности и больших размеров. Эталоны сняты на эмуляторе с программным GL, на устройстве с GPU не сверялись. Совпадение на этом входе проверяет формулу, но не гарантирует совпадение на всех картинках.

## 11. Проверки (2026-10-11, `swift test`, lint и эталоны обновлены 2026-10-13, пакет 3b)

Строки ниже взяты из вывода команд, запущенных на текущем дереве, после последней правки кода.

- `swift test` в `ios/ImageToolboxKit` (полный прогон после пакета 3b, 2026-10-13): `Test run with 1525 tests in 181 suites passed after 95.940 seconds with 50 known issues.` (код выхода 0). Все 50 known issues — расхождения 25 приближённых случаев в `AndroidReferenceParityTests` (по два условия на случай, раздел 10); после пакета 3a было 88 на 43 случая. Тестов на шесть больше, чем после пакета 3a (1519): добавлен `AireBlurQuirkTests` (рамка Aire, строки-повторы при ядре больше 61, нижняя «медиана», непрозрачность `FastBlur`, пиксель якоря у tilt-shift, форма ядра боке). Ожидания старых тестов изменены под поведение Android: круг размера 5 в морфологии (радиус 5/3, то есть блок 3 на 3), top-hat и градиент обрабатывают альфу как канал, если есть прозрачные пиксели (непрозрачная картинка получает альфу 255), медиана с радиусом 0 — окно радиуса 1 вместо тождества, `TentBlur` с размером 1 размывает (два прохода box 3), `FastBilaterialBlur` с размером 1 не тождество.
- `xcrun swift format lint --strict --recursive ImageToolboxKit/Sources ImageToolboxKit/Tests ImageToolbox/Sources ImageToolbox/UITests` в `ios` (после пакета 3b, 2026-10-13): код выхода 0, замечаний нет.
- `xcodegen generate` в `ios`: код выхода 0. `git status` по `ios/ImageToolbox.xcodeproj` пуст: pbxproj вручную не правился и не изменился. Не перезапускалось в пакете 3b: проект и список файлов приложения не менялись (новые файлы лежат в пакете ImageToolboxKit).
- `xcodebuild -scheme ImageToolbox -sdk iphonesimulator build` (после пакета 3b, 2026-10-13): `** BUILD SUCCEEDED **`, код выхода 0, строк `warning:` в логе 0.
- UI-тест `testFiltersChainShowsAddedFilter` в пакете 3b не перезапускался: экран фильтров и каркас не менялись (последний прогон — пакет 3a, `Test Case ... passed (21.536 seconds)` и `** TEST SUCCEEDED **`).
- Эталоны Android: `./gradlew :instrumentation-tests:connectedFossDebugAndroidTest ... ReferenceFilterExportTest` — `BUILD SUCCESSFUL`, на устройстве создано 112 PNG и `input.png` (2026-10-13, `BUILD SUCCESSFUL in 17s`), `adb pull` забрал 113 файлов; в репозиторий добавлено 85 новых PNG.

Проверка U+00A0 (`python3 -c "print(open('FILE','rb').read().count(b'\xc2\xa0'))"`) по всем изменённым и новым текстовым файлам даёт 0. Бинарные PNG эталонов в эту проверку не входят: в `VignetteFilter.png` встречаются байты `C2 A0` внутри сжатых данных изображения, это не текст.
