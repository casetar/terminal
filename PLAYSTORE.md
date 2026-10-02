# 🚀 Savun — Публикация в Google Play Market

> Полный чеклист и инструкция для публикации Flutter SSH Terminal в Google Play

---

## 📋 Содержание

1. [Что нужно иметь](#1-что-нужно-иметь)
2. [Шаг 1 — Google Play Console](#2-шаг-1--google-play-console)
3. [Шаг 2 — Подписание приложения (Keystore)](#3-шаг-2--подписание-приложения-keystore)
4. [Шаг 3 — Настройка Flutter для подписи](#4-шаг-3--настройка-flutter-для-подписи)
5. [Шаг 4 — Сборка AAB (Play Store формат)](#5-шаг-4--сборка-aab)
6. [Шаг 5 — Обновить pipeline.sh](#6-шаг-5--обновить-pipelinesh)
7. [Шаг 6 — Заполнить страницу в Play Console](#7-шаг-6--заполнить-страницу-в-play-console)
8. [Шаг 7 — Загрузить и опубликовать](#8-шаг-7--загрузить-и-опубликовать)
9. [Чеклист перед публикацией](#9-чеклист-перед-публикацией)
10. [Типичные ошибки](#10-типичные-ошибки)

---

## 1. Что нужно иметь

| Что | Где взять | Стоимость |
|---|---|---|
| **Google-аккаунт** | google.com | Бесплатно |
| **Google Play Console** | play.google.com/console | $25 разово |
| **JDK 17+** | adoptium.net | Бесплатно |
| **Android SDK** | Встроен во Flutter | Бесплатно |
| **Flutter SDK** | flutter.dev | Бесплатно |
| **Keystore файл** | Генерируем ниже | — |
| **Иконка приложения** | 512×512 PNG | — |
| **Скриншоты** | Эмулятор или телефон | — |

---

## 2. Шаг 1 — Google Play Console

1. Перейди на [play.google.com/console](https://play.google.com/console)
2. Оплати разовый взнос **$25**
3. Нажми **Создать приложение**
4. Заполни:
   - **Название приложения**: `Savun Terminal` (или любое)
   - **Язык по умолчанию**: Русский
   - **Тип**: Приложение
   - **Платное/бесплатное**: Бесплатное
5. Прими соглашения и нажми **Создать приложение**

---

## 3. Шаг 2 — Подписание приложения (Keystore)

> ⚠️ **КРИТИЧНО**: Keystore нельзя потерять! Без него не сможешь обновить приложение.
> Храни в нескольких местах (облако + локально).

### Генерация Keystore (один раз навсегда)

```bash
keytool -genkey -v \
  -keystore ~/savun-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias savun-key
```

Заполни данные при запросе:
```
Введите пароль хранилища ключей: [твой пароль]
Ваше имя и фамилия: Savun App
Название подразделения: Dev
Название организации: Savun
Город: Moscow
Штат: Moscow
Код страны: RU
```

### Скопировать keystore на сервер

```bash
scp ~/savun-keystore.jks root@srm.0i2.ru:/root/vpngate_flutter/savun/android/app/savun-keystore.jks
```

---

## 4. Шаг 3 — Настройка Flutter для подписи

### Создать файл с паролями

```bash
# Создать /root/vpngate_flutter/savun/android/key.properties
cat > /root/vpngate_flutter/savun/android/key.properties << 'EOF'
storePassword=ТУТ_ПАРОЛЬ_ОТ_KEYSTORE
keyPassword=ТУТ_ПАРОЛЬ_ОТ_КЛЮЧА
keyAlias=savun-key
storeFile=savun-keystore.jks
EOF
```

> ⚠️ `key.properties` добавить в `.gitignore` — там пароли!

```bash
echo "android/key.properties" >> /root/vpngate_flutter/savun/.gitignore
echo "android/app/*.jks" >> /root/vpngate_flutter/savun/.gitignore
```

### Настроить android/app/build.gradle

Открыть `/root/vpngate_flutter/savun/android/app/build.gradle` и добавить:

```groovy
// В начало файла (после apply plugin строк):
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... существующий код ...

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release  // ← добавить эту строку
        }
    }
}
```

---

## 5. Шаг 4 — Сборка AAB

> Play Store с 2021 года требует **AAB** (Android App Bundle), не APK.
> AAB меньше по размеру и оптимизируется под каждое устройство.

```bash
cd /root/vpngate_flutter/savun
flutter build appbundle --release
```

Готовый файл будет здесь:
```
build/app/outputs/bundle/release/app-release.aab
```

---

## 6. Шаг 5 — Обновить pipeline.sh

Добавь команду `--aab` в `pipeline.sh` для сборки AAB + отправки в TG:

```bash
# Уже есть в pipeline.sh команды:
bash pipeline.sh --apk   # APK full + lite → Telegram
bash pipeline.sh --aab   # AAB → Telegram (для Play Store)
```

> Функция `--aab` уже добавлена в `pipeline.sh` ниже.

---

## 7. Шаг 6 — Заполнить страницу в Play Console

### Обязательные материалы

| Материал | Размер | Формат |
|---|---|---|
| **Иконка** | 512 × 512 px | PNG, до 1 MB |
| **Feature graphic** | 1024 × 500 px | JPG/PNG |
| **Скриншоты телефона** | минимум 2 шт, мин. 320 px | JPG/PNG |
| **Краткое описание** | до 80 символов | Текст |
| **Полное описание** | до 4000 символов | Текст |

### Пример описания (скопируй и адаптируй)

**Краткое (80 символов):**
```
SSH-терминал с голосовым вводом и безопасным хранением ключей
```

**Полное:**
```
Savun Terminal — профессиональный SSH-клиент для Android.

🖥️ ТЕРМИНАЛ
• Полноценный xterm-совместимый терминал
• Подключение по SSH к любому серверу
• Поддержка UTF-8 и цветного вывода

🎤 ГОЛОСОВОЙ ВВОД
• Диктуйте команды голосом на русском языке
• Быстрый набор длинных команд без клавиатуры

🔐 БЕЗОПАСНОСТЬ
• Шифрованное хранение SSH-ключей (RSA, Ed25519)
• Поддержка аутентификации по ключу и паролю
• Импорт .pem ключей из файла

⌨️ УДОБСТВО
• Быстрые кнопки: ls, pwd, top, clear и другие
• Ctrl+C и Tab одним нажатием
• Несколько профилей серверов
• Тёмная тема

Идеально для DevOps, системных администраторов и разработчиков.
```

### Категория и рейтинг

- **Категория**: Инструменты
- **Контентный рейтинг**: Заполни анкету (займёт 5 минут)
- **Целевая аудитория**: 18+

---

## 8. Шаг 7 — Загрузить и опубликовать

1. В Play Console → **Внутреннее тестирование** → **Создать новый выпуск**
2. Загрузи `app-release.aab`
3. Заполни **Примечания к выпуску**:
   ```
   Первый выпуск — SSH терминал с голосовым вводом
   ```
4. Нажми **Сохранить** → **Проверить выпуск** → **Начать выпуск**

> 💡 Сначала выпусти во **Внутреннем тестировании** (мгновенно),
> потом **Открытое тестирование** или сразу **Производство** (ревью 1-3 дня).

---

## 9. Чеклист перед публикацией

- [ ] Создан аккаунт в Google Play Console ($25 оплачен)
- [ ] Сгенерирован и сохранён Keystore (`savun-keystore.jks`)
- [ ] Keystore скопирован в несколько мест (облако, локально)
- [ ] Файл `key.properties` настроен с паролями
- [ ] `build.gradle` настроен на подписание
- [ ] `key.properties` добавлен в `.gitignore`
- [ ] Иконка 512×512 готова
- [ ] Feature graphic 1024×500 готов
- [ ] Скриншоты (минимум 2 штуки) готовы
- [ ] Краткое и полное описание написаны
- [ ] Контентный рейтинг заполнен
- [ ] AAB собран: `flutter build appbundle --release`
- [ ] AAB загружен в Play Console
- [ ] Выпуск отправлен на ревью

---

## 10. Типичные ошибки

| Ошибка | Решение |
|---|---|
| `keystore not found` | Проверь путь в `key.properties` |
| `Wrong password` | Проверь `storePassword` и `keyPassword` |
| `APK not signed` | `signingConfig signingConfigs.release` в buildTypes |
| `Target API level` | Установи `targetSdkVersion 34` в build.gradle |
| `Missing permission declaration` | Все `uses-permission` уже есть в AndroidManifest |
| AAB > 150MB | Используй Dynamic Delivery или убери лишние ассеты |
| Ревью отклонено | Читай письмо — обычно не хватает privacy policy |

### Privacy Policy (обязательно если есть разрешения)

Так как приложение запрашивает `RECORD_AUDIO` и `INTERNET` —
**нужна ссылка на политику конфиденциальности**.

Создай простую страницу на GitHub Pages или любом хостинге:
```
https://твой-сайт.ru/privacy-savun
```

---

*Документация создана для проекта `/root/vpngate_flutter/savun`*
