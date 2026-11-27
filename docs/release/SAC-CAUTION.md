## Совместимость с Windows 11 / Windows 11 compatibility

> [!CAUTION]
> **Smart App Control (Интеллектуальное управление приложениями).**
> RDC Relay 1.6.0 распространяется без доверенной цифровой подписи. При включённом Smart App Control Windows может блокировать не только установщик, но и обычный запуск уже установленной программы. Если вы хотите сохранить эту защиту, используйте [оригинальный Desktop Commander](https://desktopcommander.app/).
>
> Отключение Smart App Control снижает защищённость всей системы: Windows перестаёт применять этот дополнительный контроль доверия к приложениям. Это не исключение только для RDC Relay. Антивирус, SmartScreen и брандмауэр отключать не требуется. RDC Relay не изменяет настройки защиты автоматически.
>
> Управление: **Безопасность Windows → Управление приложениями и браузером → Параметры интеллектуального управления приложениями**. Если вы самостоятельно приняли решение изменить настройку, здесь доступны режимы «Выкл.» и «Вкл.» (при поддержке системой). Для восстановления защиты выберите «Вкл.». Перед отключением убедитесь, что ваша версия Windows поддерживает обратное включение: на старых сборках может потребоваться сброс или переустановка Windows; возвращение в режим оценки также может потребовать сброса или переустановки. Если настройка недоступна, не изменяйте системные политики вручную.
>
> [Официальная справка Microsoft (RU)](https://support.microsoft.com/ru-ru/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions)

> [!CAUTION]
> **Smart App Control (SAC).**
> RDC Relay 1.6.0 is distributed without a trusted code-signing signature. With Smart App Control enabled, Windows may block both Setup and normal launches of an already installed copy. If you prefer to keep this protection, use the [original Desktop Commander](https://desktopcommander.app/).
>
> Turning SAC off reduces system-wide protection against untrusted applications; it is not an exception just for RDC Relay. There is no need to disable antivirus, SmartScreen or the firewall. RDC Relay never changes these security settings automatically.
>
> Manage SAC in **Windows Security → App & browser control → Smart App Control settings**. If you independently decide to change the setting, select Off or On where supported. Select On to restore protection. Before turning it off, confirm that your Windows build supports re-enabling SAC: older builds may require a reset or reinstallation, and returning to evaluation mode can also require a reset or reinstall. If the setting is unavailable, do not manually modify system policies.
>
> [Official Microsoft FAQ (EN)](https://support.microsoft.com/en-gb/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions)
