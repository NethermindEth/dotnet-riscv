# Soft-float для riscv64 (rv64im, zkVM guests) — дизайн

Цель: выполнять произвольный .NET-код с `float`/`double` на таргете без F/D
(zkEVM RISC-V target standard), вместо сегодняшней модели «в госте нет FP +
ELF-верификатор». Побочный бонус для zkVM: softfloat даёт бит-точную
детерминированность FP независимо от железа.

## Отправная точка

В RyuJIT **нет прецедента настоящего softfloat**. Единственное, что есть —
ARM32 armel (`opts.compUseSoftFP`, `JIT_FLAG_SOFTFP_ABI`): это только
*calling convention* (FP-значения в целочисленных регистрах на границах
вызовов), сама арифметика остаётся VFP-инструкциями. Опускание FP-операций в
libcall'ы (как делают LLVM/GCC при `-msoft-float`) в RyuJIT отсутствует на
всех таргетах. Поэтому дизайн трёхслойный: слой 1 портирует armel-прецедент,
слои 2–3 — новые.

## Слой 1 — soft ABI (патч 26, есть в серии)

Переиспользуем существующий `JIT_FLAG_SOFTFP_ABI` → `opts.compUseSoftFP`:

- `compiler.h`: на riscv64 `compUseSoftFP` становится динамическим полем
  (сейчас `static const false` вне arm).
- `compiler.cpp`, `compInitOptions`: riscv64 принимает флаг от VM/ilc.
- `targetriscv64.cpp`, `RiscV64Classifier::Classify`: при soft-FP скаляры
  float/double и FP-поля структур не считаются `floatFields` и не запрашивают
  `GetFpStructLowering` → всё уходит в уже существующую ветку «Integer calling
  convention», которая ровно и есть lp64.
- `compiler.cpp`, `getReturnTypeForStruct`: возврат FP-структур — та же
  логика, `FpStructLowering` не применяется при soft-FP.

Не покрыто слоем 1: возврат *скалярного* float/double остаётся в `fa0`
(`ReturnTypeDesc::GetABIReturnReg`, `genCall`, `genSimpleReturn` выбирают
регистр по регистровому классу типа). Это закрывает слой 2, переключая сам
регистровый класс `TYP_FLOAT`/`TYP_DOUBLE`. Поэтому 26 **не** самостоятельный
ABI-патч: 26–28 — одна неделимая серия (26 инертен до 27, который единственный
выставляет флаг).

Флаг по умолчанию не выставлен → патч инертен для текущих сборок.
Кто выставляет: ilc (патч 27, `CorInfoImpl` jit flags) — по **явному ABI
таргета** `TargetAbi.NativeAotRiscV64SoftFloat` (прецедент —
`TargetAbi.NativeAotArmel`; CLI-токен `--targetarch riscv64-lp64`, имя
предварительное до design-issue). ABI — свойство таргета, а не вывод из
instruction sets: `--instruction-set=-f,-d` описывает допустимые инструкции,
но не делает runtime/libm/compiler-rt lp64. От того же признака ilc пишет
`EF_RISCV_FLOAT_ABI_SOFT` в `e_flags` объектов (`ElfObjectWriter` раньше
ставил `FLOAT_ABI_DOUBLE` безусловно, и bflat правил заголовок вручную) —
lld отказывается линковать объекты с разным float-ABI. Валидация в
`RyuJitCompilation` в обе стороны: lp64d без F или D — ошибка «unsupported
configuration» (lp64f не поддерживается); lp64 с F или D в instruction sets —
тоже ошибка (у soft-таргета их нет по определению). ISA-дефолты следуют ABI:
`ConfigureInstructionSetSupport` получает `TargetAbi`, и для `riscv64-lp64`
`d`/`f` в baseline не добавляются — одного `--targetarch riscv64-lp64`
достаточно. `e_flags` собираются из двух независимых свойств:
`EF_RISCV_FLOAT_ABI_*` из ABI и `EF_RISCV_RVC` только при наличии C
(`ObjectWritingOptions.RiscV64Compressed`, из `InstructionSetSupport`).
bflat выбирает ABI, когда у zisk-таргета нет F или D (рефлексивно, чтобы
собираться и со старыми пакетами).

## Слой 2 — FP-значения в целочисленных регистрах (патч 28)

Ключевой вопрос дизайна — что делать с *типами*. Два варианта:

**(a) Ретипизация IR (первая реализация, отклонена).** В начале global morph
все `TYP_FLOAT`/`TYP_DOUBLE` заменяются на `TYP_INT`/`TYP_LONG` (lvaTable,
`ReturnTypeDesc`, call-узлы), операции — на хелперы. Бэкенд не видит FP.
Работает (валидировано: fptest_zk 39/39, bflat-ts 7000 проверок, guest
golden 69/69), но для апстрима это худший вариант: RyuJIT сознательно держит
семантические типы до конца (armel в `lower.cpp`: *«we maintain it as a
primitive type until lowering»*), а ретипизация порождает сущности —
30 непрозрачных `VNFunc`, обход cast-модели VN, «врущие» `lvaTable`/
`CallArg::m_signatureType`, per-target purity хелперов.

**(b) Типы остаются, меняется регистровый класс (текущая реализация).**
Регистровый класс типа в RyuJIT — таблица `varTypeRegister[]`
(`utils.cpp`), и практически весь бэкенд идёт через неё: `ins_Load/Store/
Copy`, `inst_Mov`, `varTypeUsesFloatArgReg` (регистр возврата в `genCall`/
`genSimpleReturn`), `genHomeRegisterParams`, `genPutArgReg` (там уже есть
ветка «float arg by integer register»), LSRA `regType()`,
`ReturnTypeDesc::GetABIReturnReg`. Под soft-float две записи таблицы
переключаются на `VTR_INT` — процесс-глобально, по прецеденту
`GlobalJitOptions::compFeatureHfa`/`compUseSoftFPConfigured` на armel
(`InterlockedCompareExchange` + `NO_WAY` при смене в течение процесса).
После этого FP-значения живут в GPR автоматически; вручную правятся только
места, которые решают по `varTypeIsFloating`, а не по регистровому классу:

- `ins_Load/ins_Store`: 4-байтный целочисленный путь на riscv64 выбирал
  `lw/sw` только для `TYP_INT` — добавлен `TYP_FLOAT`;
- LSRA: `availableRegs[TYP_FLOAT/DOUBLE] = &availableIntRegs`; `GT_CNS_DBL`
  без internal-регистра;
- `genSetRegToConst(CNS_DBL)`: битовый образ материализуется прямо в целевой
  регистр;
- `genBitCast(int ← float)`: `sext.w` — по psABI у float в GPR верхние биты
  не определены (так и возвращают compiler-rt-хелперы), а JIT riscv64 держит
  инвариант «int в регистре sign-extended». В варианте (a) эта дыра тоже была;
- `compFloatingPointUsed` («используется FP-регистровый файл») выставляется
  по `varTypeUsesFloatReg`, а не по `varTypeIsFloating` (три места);
- `emitInsLoadStoreOp`/`BuildIndir`: временный регистр адреса нужен по
  регистровому классу, не по FP-типу.

Операции опускаются в **morph, через штатные хуки**:

| Операция | Механизм |
|---|---|
| add/sub/mul/div | `fgMorphSmpOp` → `USE_HELPER_FOR_ARITH` (как `CORINFO_HELP_LMUL` на 32-бит) |
| rem | существующие `CORINFO_HELP_FLTREM/DBLREM` (без изменений) |
| neg | `BITCAST(XOR(BITCAST(x), signbit))`; константы сворачиваются сразу |
| сравнения | `fgMorphSoftFloatRelop`: хелпер + целочисленный relop против 0 (таблица ниже) |
| касты | `fgCastRequiresHelper` возвращает true для всего FP → существующий путь `fgMorphCastIntoHelper` (как x86); int32-приёмник — 64-битный хелпер + маска-клампинг |
| ckfinite | `GT_BOUNDS_CHECK((bits >> expShift) & expMask, expMask, SCK_ARITH_EXCPN)` — прецедент `hwintrinsic.cpp` |
| Math.* | `impMathIntrinsic` отказывается по *типу* (`varTypeIsFloating(callType)`) → обычный вызов; целочисленные Min/Max и `SaturateTo*` не затронуты |

VN: хелперы моделируются как операции, которые реализуют —
`VNFunc(GT_ADD)` и т.д. (точно как `LMUL → VNFunc(GT_MUL)`), `FLT2DBL/
DBL2FLT` через `fgValueNumberCastHelper`; сворачивание FP-констант — то же
хостовое, что и на hard-float таргетах (прецедент: `FLTREM → VNF_MOD`).
Свои `VNFunc` нужны только двум трёхзначным сравнениям.

### Сравнения

В compiler-rt/libgcc `__eqdf2/__ltdf2/__ledf2` — алиасы одной функции
(unordered → +1), `__gtdf2/__gedf2` — другой (unordered → −1). Двух
трёхзначных хелперов на тип достаточно для всех IL-форм одним вызовом:

| Семантика | Вызов и проверка |
|---|---|
| oeq / une | `LE == 0` / `LE != 0` |
| olt / ole | `LE < 0` / `LE <= 0` |
| ogt / oge | `GE > 0` / `GE >= 0` |
| ult / ule | `GE < 0` / `GE <= 0` |
| ugt / uge | `LE > 0` / `LE >= 0` |
| ueq | `(LE >= 0) && (GE <= 0)` — два вызова, операнды в temp'ах |
| one | `(LE < 0) \|\| (GE > 0)` — два вызова |

Для ueq/one сохранения temp'ов лежат в первом операнде AND/OR; оба операнда
содержат вызовы, поэтому `gtCanSwapOrder` их не переставит. Дерево остаётся
relop-корневым (нужно для `GT_JTRUE`).

## Слой 3 — хелперы (патч 27)

14 `CORINFO_HELP_*`: `FLT/DBL × ADD/SUB/MUL/DIV`, `FLT/DBL × CMP_LE/CMP_GE`,
`FLT2DBL`, `DBL2FLT`. Конверсии FP↔int — существующие `DBL2LNG/DBL2ULNG/
*_OVF/LNG2FLT/LNG2DBL/ULNG2FLT/ULNG2DBL` (int32-источники расширяются до
long, uint — zero-extend, что точно в знаковом хелпере).

- `corinfo.h` + `CorInfoHelpFunc.cs` (позиционно), bump JIT-EE GUID;
- `jithelpers.h`: записи `NULL` — по образцу `CORINFO_HELP_LLSH` на 64-бит;
  VM никогда не выставляет `SOFTFP_ABI` на riscv64;
- `HelperCallProperties`: pure/no-throw безусловно (без target-ifdef);
- `ReadyToRunHelper` (в хвосте, NativeAOT-only) + `CorInfoImpl.RyuJit.cs` +
  `JitHelper.cs` → символы compiler-rt (`__adddf3`, `__ledf2`, …; прецедент —
  `fmod`/`fmodf`);
- ilc: `SOFTFP_ABI` для riscv64 без `InstructionSet.RiscV64_F`.

## Тестирование

1. Локальный компиляционный loop: `~/work/nethermind/runtime.11` (sparse
   clone dotnet/runtime на SHA из `src/source-manifest.json` VMR-ветки
   `release/11.0.1xx-preview7`), `build-runtime.sh -arm64 -checked -ninja
   -configureonly -cmakeargs -DCLR_CMAKE_BUILD_COMMUNITY_ALTJITS=1` с Apple
   clang (`CLR_CC/CLR_CXX=/usr/bin/clang*`; homebrew llvm валит configure),
   затем `ninja clrjit_unix_riscv64_arm64` (~16 с инкрементально). Ветки:
   `base`, `series-a` (старая серия), `series-b` (новая).
2. Полный цикл: CI «Build .NET SDK» → bflat → bflat-ts group `softfloat`
   (19 тестов, 6983 проверки) + fptest_zk (39) + guest golden (69/69) на
   zk-testing.
3. ELF-верификатор bflat (`--error-on-*` для F/D) — release-гейт; патч 18
   (ассерт эмиттера на F/D-опкодах) — debug-гейт: любой недоопущенный
   FP-узел падает на конкретном методе в Checked JIT.
4. Для апстрима: soft-float образ NativeAOT исполняется на любом rv64gc
   (compiler-rt builtins — целочисленный код), так что тесты `src/tests/JIT/`
   можно гонять на обычном riscv-железе с `--instruction-set=-f,-d`.

## Последовательность и статус

| Патч | Содержимое | Статус |
|------|------------|--------|
| 16/17 | F/D/C/A как `InstructionSet`, дефолты | сделаны |
| 18 | FP-ассерт эмиттера | сделан |
| 26 | soft ABI + `SOFTFP_ABI` на riscv64 | сделан, build-verified |
| 27 | 14 хелперов + ilc-маппинг + SOFTFP-триггер | переписан 2026-08-26, build-verified (Checked cross JIT) |
| 28 | FP в GPR через `varTypeRegister` + опускание в morph | переписан 2026-08-26, build-verified; CI v11.0.0.x15-sf |
| 29 | `src/tests/JIT/Directed/softfloat` — бит-точный тест (исполняется на любом таргете) | добавлен 2026-08-26 |
| bflat | riscv64-бейзлайн + `-c,-a,-f,-d` для zisk | сделан |

Порядок подачи в апстрим: (1) instruction sets F/D/C/A, (2) 26–28 одной
серией после design-issue («soft-float RISC-V target»; в репозитории уже есть прецедент soft-float RISC-V в Mono:
`MONO_ARCH_SOFT_FLOAT_FALLBACK` в `mini-riscv.h`, `mono_decompose_soft_float`).

Осталось до апстрима:

* **Процесс.** Design-issue; матрица поддержки (NativeAOT-only), что с
  crossgen2/R2R (`readytorunhelpers.h` не трогаем — crossgen2 хелперы не
  запрашивает) и интерпретатором.
* **Проверка ABI рантайма.** Managed lp64 при нативном рантайме lp64d молча
  ломает P/Invoke с `double`; нужна проверка на стороне ilc/рантайма.
* **libm.** `Math.Sqrt/Pow/Sin` уходят в hard-float musl; нужен soft-float
  libm или managed-реализации.
* **Тесты** в `src/tests/JIT/` и прогон на Checked JIT.

## Ревью 2026-08-26 (`REVIEW_11_MIN.md`) — что исправлено

1. **26 как самостоятельный ABI-патч.** Согласен: скалярный FP-return
   остаётся в `fa0` до 28. Решение — не подавать 26 отдельно; серия 26–28
   неделима, формулировки выше исправлены.
2. **Гонка на `varTypeRegister`.** Записи шли до CAS и повторялись каждой
   soft-компиляцией. Теперь протокол «захватить → инициализировать →
   опубликовать»: первая компиляция процесса делает CAS `Unset →
   Initializing`, единственная пишет таблицу и публикует режим
   (`InterlockedExchange`); остальные ждут публикации и обязаны запросить тот
   же режим (`NO_WAY` иначе). Таблица никогда не пишется, пока другая
   компиляция может её читать.
3. **F без D / ABI по ISA-флагам** (повторное ревью: выводить ABI из ISA
   нельзя в принципе — ABI нативных объектов от этого не меняется). Введён
   явный `TargetAbi.NativeAotRiscV64SoftFloat` по образцу armel: от него
   JIT-флаг, ELF `e_flags` и валидация «lp64d требует F и D» в
   `RyuJitCompilation`; bflat передаёт ABI (коммит `0800a39` в
   feature/softfloat-riscv64). Открытый пункт для апстрима: `PerfMapAbiToken`
   для нового ABI сейчас маппится в `Default`.
4. **`git diff --check` на патч-файлах.** Ложные срабатывания: контекстная
   пустая строка в unified diff — это строка из одного пробела, `--check`
   видит её как trailing whitespace в *файле патча*. Так выглядят все патчи
   репозитория (например `fixup/10/.../15_*.patch`); в апстрим уходят
   git-коммиты, а не эти файлы.

### Третье ревью

5. **`riscv64-lp64` по умолчанию объявлял F/D.** ISA-дефолты теперь строятся с
   учётом `TargetAbi` (без `d`/`f` для soft-таргета), плюс обратная валидация
   «soft-таргет не содержит F/D» в `RyuJitCompilation`.
6. **`EF_RISCV_RVC` безусловно.** RVC-бит выставляется только при поддержке C
   (через `ObjectWritingOptions.RiscV64Compressed`).

Не сделано (для апстрима): CLI-тест итогового `InstructionSetSupport` для
`--targetarch riscv64-lp64` и object-header-тест `{lp64, lp64d} × {C, no-C}`;
`PerfMapAbiToken` для нового ABI.

## Остаточные замечания из dotnet/runtime#132204 (2026-08-26)

* `MathHelpers.cpp`: убрано `HOST_RISCV64`-ветвление — явная saturating-форма
  теперь безусловна (семантический no-op для arm64/loongarch, где cast и так
  насыщал), 64-битный экспорт `RhpLng2Dbl` & co остаётся под
  `!HOST_64BIT || HOST_RISCV64`. Это снимает «ifdef-путь для такой платформы»
  из возражений tannergooding.
* Патч 29 — тест в `src/tests/JIT/Directed/softfloat` (арифметика, NaN,
  unordered-ветки, насыщающие и checked-конверсии всех ширин, float↔double,
  neg, rem, вызовы, sign-extension битов float). `ckfinite` из C# не
  эмитится — покрыт только downstream-тестами.
* Черновики: `softfloat_rfc.md` (design-issue для dotnet/runtime) и
  `softfloat_pr132204_replies.md` (ответы am11 / tannergooding). Не
  опубликованы.
* Вне серии: `A` (атомики) — свойство таргета, вопрос вынесен в RFC; libm —
  ответственность toolchain'а (soft-float musl), как и сегодняшний `fmod`.

### Пятое ревью

7. **crossgen2 принимал `riscv64-lp64`.** Токен вынесен в
   `ValidArchitecturesNativeAot` (только ilc); crossgen2 отклоняет ABI сразу
   после `GetTargetSpec` (`CommandLineException`); параметр `targetAbi` у
   `ConfigureInstructionSetSupport` обязателен — новый caller не потеряет ABI
   молча.
8. **Патч 29 в обычном CI идёт hard-float.** Так и есть: upstream-CI не имеет
   lp64-сисрута (runtime, libc, compiler-rt под `-mabi=lp64`), без него
   soft-образ не слинковать — это ровно тот downstream-слой, который не
   предлагается в апстрим. Поэтому тест позиционируется как portability
   baseline + семантическая спецификация; soft-path regression автоматизирован
   в этом репозитории: `run_x15.sh` на zk-testing NativeAOT-компилирует тот же
   `SoftFloat.cs` bflat'ом с soft ABI (`zisk_sim`), исполняет на rv64gc под
   qemu-user (ожидается exit 100), проверяет `e_flags` (soft float ABI, без
   RVC) и гейты `--error-on-float-binary/-compressed/-atomic`. CLI-тест
   отказа crossgen2 и object-header-тест — по-прежнему не написаны.

### Самопроверка после седьмого ревью (2026-08-26)

9. **Опускание на месте ломало маленькие узлы.** `USE_HELPER_FOR_ARITH` и
   `fgMorphCastIntoHelper` делают `ChangeOper(GT_CALL)` на исходном узле, а
   importer выделяет «большие» узлы только для `mul/div/rem` и `conv`
   (`callNode`); `add`/`sub` и `impImplicitR4orR8Cast` — маленькие. В Checked
   это assert `GTF_DEBUG_NODE_LARGE`, в Release — запись за пределы узла.
   Теперь `fgMorphSoftFloatArith`/`fgMorphSoftFloatCast` строят новый
   call-узел (со сворачиванием констант как у оригиналов); операнды разной
   ширины (на IL-стеке один тип F) приводятся к типу узла.

Остатки ревью закрыты (2026-08-27): 14 хелперов помечены `isNoGC` (группа
`CORINFO_HELP_LLSH`); `ElfObjectWriter.GetRiscV64ElfFlags(abi, options)` +
`ILCompiler.Compiler.Tests/RiscV64ObjectWriterTests` (4 комбинации
`{lp64, lp64d} × {C, no-C}`, `InternalsVisibleTo` для тестов);
`ILCompiler.ReadyToRun.Tests`: `RiscV64SoftFloatTargetIsRejected` — раннер
получил `CrossgenCompilation.ExpectedFailure`. Открытым остаётся только
`PerfMapAbiToken` (решение владельцев, вынесено в RFC).

libm: rootfs с коммита `36bc08b` собирает musl под rv64im, и `musl/libc.a`
в пакете SDK имеет `e_flags=0x0` у всех членов — libm (sqrt/floor/…)
soft-float; отдельный «soft-float libm» больше не нужен.

### Первая runtime-валидация x15 (2026-08-27) — что нашлось

10. **Регистр возврата FP-значений оставался `fa0`.** Все 20 тестов упали в
    ziskemu на `fmv.x.d`/`fmv.x.w`: после каждого `jalr __adddf3` JIT
    переносил результат из `fa0` в `a0`. Аргументы шли верно (классификатор
    26), а регистр возврата выбирается через `varTypeUsesFloatArgReg`, которая
    на не-ARM64 таргетах — `varTypeIsFloating`, а не регистровый класс. На
    riscv64 она теперь следует `varTypeUsesFloatReg` (как на ARM64). ISA-гейт
    bflat (`--error-on-float-binary`) поймал это на сборке — 53 инструкции в
    `abi_calls`, все в managed-коде; `e_flags` у всех образов `0x0` ✓.
11. **Тест 29 не компилировался/ошибался в ожиданиях.** Локальный прогон
    (`dotnet run`, hard-float arm64) нашёл: лямбды `() => checked((int)…)`
    невалидны как `Action` (теперь `Func<object>`), маска unordered-веток для
    упорядоченных операндов `2+4+16`, а не `1+2+4+16`. Проверки насыщения в
    малые типы (`(byte)300.0 == 255`) — семантика .NET 11 (`fgMorphExpandCast`
    в дереве 11 клампит явно); локальный .NET 10 усекает, поэтому там они
    падают ожидаемо. Правило: тест гонять локально до отправки.
12. Инфраструктура zk-testing: контейнер `Dockerfile.build` не задаёт
    `BFLAT_LD=/usr/bin/lld`, а bundled `lld` из SDK собран на ubuntu 24.04
    (libicu74) — в скриптах добавлен `-e BFLAT_LD=/usr/bin/lld`.
13. **CQ: FP-параметры были address-exposed.** `lvaInitUserArgs` под
    `compUseSoftFP` помечает FP-параметры address-exposed — armel-обход
    (значение живёт в VFP, приходит в GPR). На riscv64 lp64 это делало каждый
    float/double-параметр стековым (видно в дизассемблере `Sum10`). Условие
    переведено на `varTypeUsesFloatReg`; то же для callee-save-предпочтений FP
    локалов в LSRA (`lsrabuild.cpp`, набор кандидатов и так строится по
    `regType()`). Для armel поведение не меняется.
