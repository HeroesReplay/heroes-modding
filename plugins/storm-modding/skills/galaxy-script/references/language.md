# Galaxy language details

Statements marked (SC2) come from StarCraft II documentation and were not checked separately in
Heroes; everything else was seen in Heroes code (the game's own `TriggerLibs` or Heroes Rogue).

## Syntax

- C-like and statically typed; one pass, so declare before use. Function prototypes are legal:
  `void libMyMd_Setup ();` above the caller, body later.
- Comments: `//`. No preprocessor: no `#define`, `#if`, macros. Use `const` and `include`.
- Operators: `+ - * / %`, `+= -= *= /=`, `== != < <= > >=`, `&& || !`, `& | << >>`. No `++`/`--`.
  No ternary `?:` and no `switch` in any Heroes library; write `if / else if` chains.
- Control flow: `if/else`, `while`, `for (init; cond; step)` with any clause empty,
  `do { } while (cond);`, `break`, `continue`, `return`. No declarations inside `for (...)`.
- Locals are declared at the top of the function, before the first statement. Initializers may be
  any expression.
- `const` works for globals and locals and can build on other constants
  (`const int kMax = libCore_gv_bALMaxPlayers + 1;`).
- `static` limits a function to its file (SC2 docs).
- `native` is only for engine functions; don't declare your own.

## Types

| Type | Notes |
| --- | --- |
| `int` | 32-bit signed |
| `fixed` | fixed point, 12 fractional bits (about 0.000244 resolution), range about plus or minus 524287.999. int converts to fixed implicitly; back with `FixedToInt` (truncates) or `RoundI`/`CeilingI`/`FloorI` |
| `bool` | no implicit int conversion; `BoolToInt(b)` |
| `string` | plain, case-sensitive when compared with `==`. Game links (unit, behavior, effect, ability ids), bank keys, catalog field paths and layout frame paths are all strings. A string can be `null` or `""`; check both |
| `text` | localized display text for UI natives. `StringExternal("Key")`, `StringToText`, `IntToText`, `FixedToText(f, c_fixedPrecisionAny)`; `+` concatenates. HotS has no `TextToString` |
| handles | `unit`, `unitgroup`, `unitfilter`, `point`, `region`, `timer`, `trigger`, `playergroup`, `bank`, `actor`, `actorscope`, `abilcmd`, `order`, `sound`, `soundlink`, `revealer`, `color`, `camerainfo`, `transmissionsource`, `effecthistory`, `doodad`, `unitref` |
| int ids | dialogs, dialog controls, text tags, stat events |

From `natives.galaxy`: `abilcmd`, `bank`, `camerainfo`, `marker`, `order`, `playergroup`, `point`,
`region`, `soundlink`, `string`, `text`, `timer`, `transmissionsource`, `unitfilter`, `unitgroup`
and `unitref` are deleted automatically when nothing references them; other objects (dialogs,
text tags, units) must be destroyed explicitly. `==` compares contents for `abilcmd`, `point`,
`string`, `unitfilter` and `unitref`, and references for the rest.

## Arrays and structs

- `int[10] a;` and `string[kMax + 1] names;`; sizes are compile-time constants, indices start at 0.
  Generated code sizes player arrays `N + 1` to index by player number 1..N.
- Multi-dimensional: `int[A][B] grid;`.
- `struct Name { int a; string b; };` (trailing `;`). The editor calls them records and names them
  `lib<ID>_gs_<Name>` with `lv_` members.
- Structs are not passed by value: use `structref<Name>` parameters. Copy field by field.
- `arrayref<T>` and `funcref<F>` exist (SC2); Heroes code rarely uses them.
- No dynamic allocation. For key-value storage use the data table:
  `DataTableSetInt(true, "key", v)` (global) or `false` (local to the running trigger). Global
  entries live until `DataTableValueRemove`.

## Functions

- `type Name (type a, type b) { ... }`; `void` for none. No overloading, no default arguments;
  natives use suffixes (`MaxI`/`MaxF`, `AbsI`/`AbsF`, `ModI`/`ModF`).
- Recursion works; depth is limited (limit not documented).

## Threads and limits

- Each trigger firing runs in its own cooperative thread; only one runs at a time. `Wait(t,
  c_timeGame | c_timeReal)` suspends the current thread.
- A `Wait` in a function blocks its caller. Start work you don't want to wait for with
  `TriggerExecute(t, true, false)`.
- `TriggerQueueEnter()` / `TriggerQueueExit()` serialize triggers that share state (46 uses in
  Heroes Rogue).
- A thread that runs too long without yielding is stopped with an execution-limit error. Yield in
  big loops.
- Code size plus global variables share a fixed memory budget; large global arrays count against
  it (SC2 docs).
- Run-time errors (index out of range, division by zero, invalid handle) stop the thread.

## Editor and hand-written code

- The editor's `Triggers` file is the source; it regenerates `MapScript.galaxy` and each library's
  `.galaxy` on save. A Custom Script element is emitted near the top of the map script; the
  SC2Mapster pattern is one Custom Script holding `include "scripts/MyCode"` with the real code in
  loose files next to the map.
- A GUI function marked "Native Function" with the same name and parameters calls your script
  function from GUI triggers.
- Script code reaches a GUI global by adding the `gv_` prefix itself.
- Saving a document as components (a folder) keeps loose script files next to it.

## Text in script

- `StringExternal("Key")` reads `GameStrings.txt`. Keys can be built at run time
  (`StringExternal("MyMod/Tooltip/" + name)`).
- Parameterized text: put `Param/Expression/MyKey=Gained ~A~ gold` in `GameStrings.txt`, then
  `TextExpressionSetToken("Param/Expression/MyKey", "A", IntToText(n));` and
  `TextExpressionAssemble("Param/Expression/MyKey")`.
- Markup inside values: `<n/>` new line, `<c val="FFDE36">` colour, `<s val="Style">` style,
  `<d ref="Effect,MyDamage,Amount"/>` live data, `<d ref="($GalaxyVar:libMyMd_gv_bonus$)*100"
  precision="0"/>` a script global, `<img path="@UI/Icon"/>` inline image.
