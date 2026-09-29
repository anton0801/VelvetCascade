# Velvet Cascade

Театральная match-3 головоломка для iOS 15+ (SwiftUI, архитектура CLEAN): игрок собирает совпадения, заряжает
способность шута-дирижёра Vell и поворачивает сцену на 90°, меняя направление гравитации. 180 уровней в 9 мирах,
ежедневный бонус Daily Encore, полностью офлайн.

Спецификация: `docs/spec/MASTER_PROMPT_RU.md` (копия исходного ТЗ) и `docs/spec/LEVEL_BRIEFS.csv`.
Фактический статус каждого пункта: `docs/IMPLEMENTATION_CHECKLIST.md`, передача работ: `docs/HANDOFF.md`.

## Открыть и собрать

Единственный проект: **`VelvetCascade.xcodeproj`** (схема `VelvetCascade`, shared). Xcode 16.4, iOS Simulator 18.5.

На этой машине `xcode-select` указывает на Command Line Tools, поэтому команды используют `DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VelvetCascade.xcodeproj -scheme VelvetCascade \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build/DerivedData build
```

Тесты:

```bash
# Domain-движок (macOS, быстро): 69 тестов
cd Packages/VelvetCore && swift test
# Приложение: 24 unit (хранилище, импорт, Daily, 180 уровней из бандла) + 8 UI-тестов XCUITest (iOS Simulator)
xcodebuild -project VelvetCascade.xcodeproj -scheme VelvetCascade \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build/DerivedData test
```

Вспомогательные скрипты: `scripts/build_install.sh` (сборка + установка на симулятор),
`scripts/capture_all.sh <udid> <label>` (скриншоты всех DEBUG-фикстур), `scripts/gen_docs.py` (отчёты из данных).

## Архитектура

| Слой | Где | Что |
|---|---|---|
| Domain | `Packages/VelvetCore/Sources/VelvetDomain` | Чистый Swift, без SwiftUI/SpriteKit: `Board`, `Cell`, `Occupant`, `GameState`, `BoardTransform` (R(x,y)=(N−1−y,x)), `MatchResolver`, `GameEngine` (wave-resolver, Curtain Sweep, gravity/refill, keys, deadlock), `ChargePolicy`, `WinPolicy`, `HintPolicy`, `DailyRewardPolicy`, `LevelValidator`, детерминированный `LevelRNG` (SplitMix64), `StateHasher` |
| Application | `VelvetCascade/Application` | `ProgressStore` (атомарные сценарии: StartLevel, CommitResult, ClaimDaily, ImportSave, ResetProgress, Save Retry) и `GameSession` (ExecuteAction, PreviewTurn, RequestHint, RestartRun, renderer событий) |
| Data | `VelvetCascade/Data` | `AtomicProgressRepository` (versioned JSON: temp-write → replace, предыдущая версия → backup), `SettingsRepository` (отдельно от run), `BundleLevelRepository`, `MediaManifestRepository`, `BackupCodec` (export/import с SHA-256 checksum и полной валидацией) |
| Presentation | `VelvetCascade/Presentation`, `App` | Координатор 22 маршрутов для iOS 15 (`Router`, без NavigationStack), экраны, компоненты UI01–UI20, `BoardView` (поворот с масштабом 1/(\|cos\|+\|sin\|), hit testing через inverseR), `AccessibilityBoardAdapter` |
| Services | `VelvetCascade/Services` | `AudioService` (шины Music/SFX/Ambience, 10 голосов с приоритетами, duck −6 dB, crossfade 600 ms, `.ambient` — уважает Silent Mode), `HapticsService`, `Clock`, `SecureRandom` (SecRandomCopyBytes, без modulo bias), `ImageLoader` (ImageIO-даунсэмплинг) |
| Debug | `VelvetCascade/Debug` | DEBUG-фикстуры для скриншотов (`-VCFixture <name>`), в release не создаются |

Порядок хода: Domain рассчитывает settled-состояние → `ProgressStore` атомарно сохраняет его (или результат + best +
unlock + first-clear ledger + награду одной транзакцией) → renderer проигрывает события. Ошибка записи возвращает
прежнюю модель и открывает Recovery (Retry повторяет тот же transactionID).

## Уровни (LevelForge)

`Packages/VelvetCore/Sources/LevelForge` — генератор/солвер/валидатор на том же Domain-движке:

```bash
cd Packages/VelvetCore && swift build -c release
./.build/release/LevelForge build  --root ../.. [--levels 1-180] [--jobs 8]   # генерация + решение + баланс
./.build/release/LevelForge verify --root ../..                              # валидация + replay всех 180 JSON
./.build/release/LevelForge inspect --root ../.. --level 21                  # ASCII-разбор решения
```

Каждый `VelvetCascade/Resources/Levels/level_XXX.json` содержит полный `LevelDefinition` (маска, слои, ключи/выходы,
цели, seed) и `solutionTrace` с hash после каждого действия. Баланс измеряется ботом, который не подглядывает в
будущий refill; это автоматическая оценка, **не ручной playtest** (см. `docs/LEVEL_BALANCE_REPORT.md`).

## Медиа

* **Графика** (40 PNG, `VelvetCascade/Resources/Art`): инструмента генерации изображений в среде не было, поэтому вся графика
  нарисована процедурно в коде (`Production/ArtSources/ArtForge`, CoreGraphics). Пересборка:
  `cd Production/ArtSources/ArtForge && swift run -c release ArtForge`, проверка: `python3 scripts/art_qa.py`.
  Подробности и ограничения: `docs/ART_PRODUCTION.md`.
* **Звук** (44 файла, `VelvetCascade/Resources/Audio`): пайплайн ElevenLabs `scripts/generate_audio.py`
  (`dry-run`, `generate --ids …`, `build-runtime`, `qa`, `approve`). Сырые ответы и мастера — `Production/AudioRaw/`.
  Статус и команды: `docs/AUDIO_PRODUCTION.md`.

### Переменные окружения

| Переменная | Где | Назначение |
|---|---|---|
| `ELEVENLABS_API_KEY` | окружение или локальный `.env` (в `.gitignore`) | только для `scripts/generate_audio.py` на машине разработчика |

`.env.example` содержит только имя переменной. Ключ не попадает в Swift, Info.plist, ассеты, манифесты, логи и
экспорт прогресса; приложение не обращается к сети вообще. `scripts/audio_qa.py` проверяет отсутствие ключа в
ресурсах и манифестах.

## Ограничения (кратко; полный список — docs/HANDOFF.md)

* Ручной playtest 180 уровней не выполнялся; решаемость доказана солвером, сложность оценена ботом.
* Музыка M01–M03 — процедурные заменители: Music API ElevenLabs вернул HTTP 402 (нужен платный план).
  Прослушивание (listening QA) звуков человеком не проводилось, поэтому ни один ID не помечен `approved`.
* Графика процедурная (2D с 3D-освещением), не рисованная и не сгенерированная моделью.
* Тестирование на физическом устройстве не выполнялось (только iOS Simulator 18.5).
