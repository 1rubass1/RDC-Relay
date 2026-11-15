# REV-R1-004 — независимая повторная проверка R3: partial JSON / read failure / remainder

**Дата:** 2026-11-15. **Исполнитель:** 🔍 Ревьюер 1 — дополнительная независимая проверка по прямому поручению владельца, закрывающая технический объём следующего R2-review; **не** заявка о работе от имени другого зарегистрированного чата «🔍 Ревьюер 2».

**Объект:** локальный, **ещё не опубликованный в GitHub**, коммит `5dfa65c4a449dc3119c37cfc4784f63aa8510bd5` ветки `fix/rc1-r3-observer-partial-stream`, отдельная чистая рабочая копия STARMER `RDC-Relay R3 PartialStream Fix Work`; база `1e59de4b978965d222c5733839db935574c47563`. Исправление адресует [REV-R2-003-F1/P2](REV-R2-003-READINESS-1E59DE4.md). Из шести изменённых файлов функция обработки ошибки в `Source/rc1-remote-observer.ps1` и её новые тесты проверены предметно. Ни одного файла реализации Reviewer не менял.

**Вердикт: CONDITIONAL PASS для исходного R2-003-F1** и фактического артефакта. **NEEDS DECISION / отдельный P2-liveness случай после ошибки callback на границе завершённой строки**, см. ниже. **Выпуск, установка, настоящая сессия Remote/OAuth — NO-GO/NOT CHECKED.**

## Независимые STARMER Windows PowerShell 5.1 результаты

| Проверка | Измерено Reviewer |
| --- | --- |
| `Test-V16R3ObserverStreamAfterFailure.ps1` на коде коммита | **19 PASS / 0 FAIL / exit 0** |
| Та же suite на точном `package/Source/rc1-remote-observer.ps1` в новом dist | **19 PASS / 0 FAIL / exit 0** |
| Прежняя R2-002-F1/F2 suite на точном `package/RdcOwnerRuntime.dll` + упакованный observer | **22 PASS / 0 FAIL / exit 0** |
| `Invoke-V16Rc1SafeRegression.ps1` (полный, без фильтра) | **71/71 suites PASS / 0 FAIL / exit 0** |
| `Test-V16StandaloneSetup.ps1 -SetupPath <точный новый Setup>` | **22 PASS / 0 FAIL / exit 0**, реальный Setup.Main не запускался, embedded payload извлечён/проверен/удалён в одноразовой директории |
| `Test-V16PortableDoubleClick.ps1 -PortableZip <точный ZIP>` | **10 PASS / 0 FAIL / exit 0** в уникальном TEMP, запуск Launcher через ShellExecute только с **подменённым на инертный** fake Host, активация тестового event; полный живой Remote не запускался |
| Независимый просмотр ZIP и staging через .NET | **22/22 manifest SHA совпали**, **23/23 ZIP members** byte-hash совпали с package; **0** пропущенных/неизвестных ZIP members. Дополнительный staging-файл `RC1 Pilot Setup.exe` намеренно **не входит в Portable ZIP/manifest**, является отдельным Setup |
| Git и очистка | HEAD точно `5dfa65c...`, ветка `fix/rc1-r3-observer-partial-stream`, рабочая копия clean, `git diff --check` 0; 0 новых `RDC-RC1-R3-PARTIAL-*.log`, `RDC-R1-STREAM-BOUNDARY-*`, `RDC-RC1-R2-READINESS-*`, `RDC-RC1-EXE-*`, `RDC-RC1-PORTABLE-TEST-*` |

**Точный новый частный пакет** `dist/RDCRelay-1.6.0-RC1-Full-72ccce2058e042a0b117739eab4e9019`:

- Setup SHA-256: `36F2E4CBCB98998B9649CA74D1D1976FA964DA74D419467E228711C1A2CF5680`.
- Portable ZIP SHA-256: `F9D334229B868D8EF4DC103A696F1E5D82E8ADC5D55F5231EA31679F5DDA70C5`.
- Observer Source и точно упакованный observer имеют **одинаковый** SHA-256 `49AF252A9336B79873DF6EDA2E5170F1E0FB23B4BAB384E20B4182D93E32B800`.
- В отдельной упакованной RC1 candidate-конфигурации `installable=true`, `publishable=false`, `autoUpdateEnabled=false`. Это **не разрешение устанавливать или публиковать**; исходная рабочая копия осталась нетронутой, стабильная версия `1.5.18`.

## Исходный дефект R2-003-F1 — устранён, независимое A/B-воспроизведение

Reviewer дополнительно написал **одноразовый собственный in-memory/временный** probe с реальным `FileStream`, `FileShare.None`, продакшен-функциями `Invoke-Rc1RemoteObserverPoll`, UTF-8 decoder и classifier; заглушена **только проверка OS-идентичности Remote**. Тест создал отдельный короткоживущий тестовый `*.log`, затем точно его удалил. Сценарий:

1. Прочитать незавершённый `{"message":"`; сохранились Offset и Fragment.
2. Вызвать poll при эксклюзивно заблокированном файле. Catch выставляет Fault/обнуляет Ready proof.
3. Снять блокировку, дописать `Desktop Commander Remote is connected"}\n` к **той же** JSON-строке, ещё раз poll.

**На базовом `1e59de4`: `Ready`, 1 ложный marker. На новом `5dfa65c`: `Fault`, 0 markers.** Это непосредственно закрывает прежнюю регрессию, а не просто повторяет собственную штатную suite Programmer.

Также новая suite на точно упакованном файле подтверждает: настоящий отдельный полный status-line позднее корректно ставит `Ready`; ошибка пустого log не восстанавливает прежний Ready без доказательства; незавершённый 4-байтный emoji после sharing fault декодируется без U+FFFD; слишком длинная физическая строка не превращает suffix в состояние связи; ошибка callback после потребления байтов инвалидирует старое доказательство и защищает partial JSON suffix.

## R1 — дополнительный, независимо воспроизведённый P2-liveness edge case: callback fault **после уже завершённой строки**

**Точка:** `Source/rc1-remote-observer.ps1`, catch `if($readBytesConsumed){ Reset-Rc1ObservedUtf8Stream $ob; $ob.DiscardOversizedLine=$true }`. Flag отражает, что байты прочитаны, но **не различает**, существовал ли неполный хвост физической строки.

Контрольное собственное A/B-воспроизведение: полностью записать **только** `Channel closed\n` (с LF), на её `owner.ObservedMarker` один раз инъецировать исключение **после полного FileStream.Read**. Затем добавить **одну самостоятельную полноценную** `Desktop Commander Remote is connected\n` и повторить poll; далее добавить вторую такую строку.

| Наблюдение | Предыдущее `1e59de4` | Новое `5dfa65c` |
| --- | --- | --- |
| После callback exception | Fault, `DiscardOversizedLine=false` | Fault, `DiscardOversizedLine=true` |
| После первого полного нового Ready-маркера | **Ready**, marker 1 | **Fault**, marker 0 |
| После второго полного Ready-маркера | Ready, marker 2 | Ready, marker 1 |

Новый код **не сообщает ложного Ready** и поэтому улучшает fail-closed безопасность исходного случая. Но когда исключение произошло **на границе строки, без фрагмента**, флаг discard подавляет **следующую целиком новую строку**, а не остаток прежней. При одиночном реальном reconnect-событии пользователь может остаться в `Fault` до ещё одного допустимого status-маркера. Это **подтверждённый пограничный риск потери сигнала восстановления**, не доказательство живого Remote outage и не автоматический release blocker без принятого критерия liveness. В [Programmer follow-up](../planning/V1-6-0-RC1-R2-003-PARTIAL-STREAM-FOLLOWUP.md) допущено консервативное пропускание строки после mid-poll error, поэтому необходима **явная оценка Architect**: приемлем ли такой fail-closed компромисс для завершённой строки. Если нет, добавить phase-aware line-boundary-state + отдельную fault-injection проверку single fresh marker при исключении ровно на LF. **Нельзя просто отключить discard для всех post-read ошибок:** это вернёт исходное ложное Ready на JSON suffix.

## Scope / решение

**GO** Architect для признания узкого исправления R2-003-F1 на исходниках и новом частном Setup/Portable в измеренном объёме. **NEEDS DECISION** по описанному R1/P2; за пределами текущего исправления остаются настоящий Remote 0.2.52, cold start, GUI/tray physical click, DPI, OAuth, установка/обновление и стабильный выпуск, а также продуктовая приёмка двухминутного периода без подтверждения канала. Пользовательские процессы, журналы, учётные данные, установленный продукт, Desktop Commander Remote, main/stable и общий update feed не менялись.

**Статус источника:** коммит `5dfa65c` существует пока только локально на STARMER, поэтому проектная ссылка на GitHub commit/PR **не выдаётся** как существующая. Отчёт сохраняется в `development` исключительно как независимое review-evidence; не означает merge/push/release этого кода.
