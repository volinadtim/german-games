# eskiNess на Android — как собрать APK

Игра уже готова к экспорту: в папке есть пресет **Android** (`export_presets.cfg`),
мобильный рендер и экранное управление. Нужно один раз подготовить компьютер, потом
собирать в пару кликов.

## 1. Что поставить (один раз)

1. **Godot 4.7.2** — тот же, которым открываешь игру.
2. **Шаблоны экспорта** для 4.7.2.
   В Godot: `Редактор → Управление шаблонами экспорта… → Загрузить и установить`.
   Если не качается, скачай `Godot_v4.7.2-stable_export_templates.tpz` с godotengine.org
   и выбери его там же через `Установить из файла`.
3. **JDK 17**, например Eclipse Temurin 17: <https://adoptium.net/temurin/releases/?version=17>.
   Ставь в папку по умолчанию, обычно `C:\Program Files\Eclipse Adoptium\jdk-17...`.
4. **Android SDK, минимальный набор.** Android Studio целиком не нужна.
   - Скачай **Command line tools only** для Windows: <https://developer.android.com/studio#command-tools>.
   - Создай папку `C:\Android\Sdk\cmdline-tools\latest` и распакуй туда архив так,
     чтобы получилось `C:\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat`.
   - Открой PowerShell и выполни:
     ```
     $env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot"   # свой путь к JDK
     cd C:\Android\Sdk\cmdline-tools\latest\bin
     .\sdkmanager.bat --licenses
     .\sdkmanager.bat "platform-tools" "build-tools;35.0.1" "platforms;android-35"
     ```
     На каждый вопрос про лицензии отвечай `y`.
     Если Godot потом попросит другую версию build-tools, поставь её той же командой.

## 2. Указать пути в Godot (один раз)

`Редактор → Настройки редактора → Экспорт → Android`:

- **Java SDK Path** — папка JDK 17, например `C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot`.
- **Android SDK Path** — `C:\Android\Sdk`.
- **Debug Keystore** — смотри следующий шаг.

## 3. Debug keystore (ключ для отладочной подписи)

Обычно Godot создаёт его сам, когда указан путь к JDK: поле **Debug Keystore**
заполняется автоматически, логин `androiddebugkey`, пароль `android`.

Если поле осталось пустым, создай ключ вручную в PowerShell:

```
& "C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot\bin\keytool.exe" -genkeypair -v -keystore C:\Android\debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" -deststoretype pkcs12
```

Затем в настройках укажи:

- **Debug Keystore**: `C:\Android\debug.keystore`;
- **Debug Keystore User**: `androiddebugkey`;
- **Debug Keystore Pass**: `android`.

⚠️ Ключи и пароли **не коммить** в репозиторий, он публичный.
Они хранятся в настройках редактора, а не в папке игры, и это правильно.

## 4. Собрать APK

1. Открой проект игры в Godot.
2. `Проект → Экспорт…` и слева выбери пресет **Android**.
3. Если внизу красный текст, там написано, чего не хватает (шаблонов, SDK, ключа).
   Исправь по шагам выше.
4. Нажми **Экспортировать проект…**, оставь галочку **Экспорт в режиме отладки**
   и сохрани, например, в `build/eskiNess.apk`. Папка `build/` в git не попадает.

## 5. Поставить на телефон

Способ А, проще всего:

1. Скинь `eskiNess.apk` на телефон через кабель, Telegram или облако.
2. Открой файл на телефоне и разреши «установку из неизвестных источников», когда спросит.

Способ Б, по кабелю одной кнопкой:

1. На телефоне: `Настройки → О телефоне`, 7 раз нажми на «Номер сборки».
   Потом `Для разработчиков → Отладка по USB`.
2. Подключи телефон кабелем и разреши отладку на экране телефона.
3. В Godot справа вверху появится значок Android. Нажми его, и игра поставится
   и запустится сама.
4. Можно и командой: `C:\Android\Sdk\platform-tools\adb.exe install -r build\eskiNess.apk`.

## Что в игре по-другому на телефоне

- **Управление.**
  - Джойстик слева: ходьба, а если толкнуть до упора вперёд — бег.
  - Свайп по правой половине экрана: обзор.
  - Кнопки: УДАР (если кулаки опущены, сначала поднимает их), СТОЙКА, ПРЫЖОК,
    E (взаимодействие), СВЕТ (фонарик), МАСКА (противогаз), ЛЕЧИТЬ, СУМКА (инвентарь), II (пауза).
  - Ячейки хотбара 1–5 внизу нажимаются пальцем.
- **Графика.** Рендер Mobile (Vulkan), а на старых телефонах без Vulkan — Compatibility
  (OpenGL). На телефоне нет SSAO, отражений SSR и объёмного тумана, остальное то же.
  На ПК всё как было.
- **Проверить кнопки на ПК** можно запуском с флагом `--touch`:
  `godot --path <папка игры> -- --touch`. Мышь при этом кнопки не нажимает, нужен сенсорный экран.

Версию для нового APK меняй в `Проект → Экспорт → Android → Version → Code`
(просто +1), иначе телефон может не захотеть ставить поверх старой.
