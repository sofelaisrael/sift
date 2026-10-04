# DESIGN-BRUTALIST.md — Neobrutalism for SIFT

**Status:** IMPLEMENTED, twice. The tokens are `lib/theme/brutal_tokens.dart`, the controls are `lib/widgets/brutal_{button,chip,field,activate}.dart` plus the shared `brutalEdge(...)` factory in `brutal_chip.dart`, and the grammar now reaches **30** buttons, 5 fields, 3 chip classes, the capture sheet's `_SourceOption` pair, `switchTheme`, **and** the read-only surfaces specified in §4.9–§4.16 — backed by 7 `test/brutal_*_test.dart` files.
**Scope:** visual treatment of **all** surfaces, interactive and read-only. The first pass covered interactive surfaces only; §1 records that rule, why it was reversed, and what it cost. Colour personality is unchanged: the palette is still warm paper carrying hard edges.
**Grounding:** every count, path, and line number below was read from the working tree. Every contrast ratio shows its arithmetic. Every Flutter API claim is marked VERIFIED or UNVERIFIED.

---

## 1. The rule

> ### **The first rule, and why it is no longer the rule**
>
> > **Brutalism marks what you can touch. Warmth marks what you read.**
>
> This governed the first pass. **It has been reversed.** Read the reasoning
> below before changing anything here again, because the reversal was made on
> evidence rather than on taste.

### What the first pass believed

The app originally had **no consistent signal for "tappable."** Look at what a
user actually saw:

- A screenshot card was a `paper`-filled 20pt-radius rect with a 1pt `divider`
  hairline and an L1 shadow (`cardTheme`, `app_theme.dart:640-653`).
- A FilledButton was an `accentDeep`-filled rounded rect with **no border at all**
  (`filledButtonTheme`).
- A filter chip was a `paper`-filled 999-radius capsule with a 0.5pt hairline.
- A settings row was a bare `InkWell` with no fill, no border, no shadow.

The narrow fix was to give hard edges exactly one meaning — *this is a
control* — and to leave read-only content warm so the signal stayed legible. §6.1
predicted, correctly, that this would look like a collision: a 2pt hard-edged
terracotta button sitting inside a soft, 20pt-radius, hairline-bordered paper
card reads as two design systems in one screen.

### Why it was reversed

The user reviewed the accent-only build **on a device** and rejected it: the
remaining visual style of the app did not go with the buttons, and the design
should go full on it. Two things were wrong with the narrow rule, and only one
of them was visible in a screenshot:

1. **The narrow rule was not neutral — it made a promise it did not keep.** "Hard
   means operable" is only a grammar if hard is *rare*. In practice the hard
   edges were concentrated in action rows, empty states and dialog footers,
   which is not a distribution a reader learns; it is one they have to keep
   checking. Meanwhile the hairlines it implicitly blessed were arithmetically
   blind: `divider` on `paper` measured **1.42:1** light and **1.22:1** dark, on
   a card that is an `InkWell`, i.e. a UI component boundary owed 3:1 (SC
   1.4.11). The rule was not protecting a distinction; it was licensing a
   defect.
2. **A container and its contents came from different systems.** The §2.5
   exclusion "a container is not a control" is true and irrelevant: nobody reads
   a dialog's chrome as operable. What they read is *coherence*. A 24pt-radius
   warm sheet around two hard-edged tiles, or a warm card around hard buttons,
   is a visible seam — and a seam is the one thing a single visual language is
   supposed to eliminate.

### The rule now

> **One hard-edged language across every surface. What you can touch still
> differs from what you read — in depth, in fill, and in state — but never in
> grammar.**

Concretely, and this is the whole of it:

| | Radius | Edge | Shadow |
|---|---|---|---|
| Read-only surface | `rControl` 4 | 2pt, scored against **its own fill** | hard, one direction |
| Control | `rControl` 4 | 2pt, scored against **its own fill** | hard + press translate |
| Read-only **label** | `rControl` 4 | 2pt | **none** — see §4.12 |
| **Excluded** (§2.5) | unchanged | hairline | soft L1–L5 |

The hierarchy is carried by *depth and state*, not by a second visual language:
a read-only surface casts, a label does not; a control sinks and rings, a surface
does not. Warm paper survives as the **fill** — every one of these surfaces is
still cream, and the palette is untouched — so the app reads as warm paper
carrying hard edges rather than as a generic brutalist skin.

### Why this is a grammar and not a decoration

One direction of light, one corner radius, one edge weight, one shadow offset,
everywhere. That is what makes the app look built rather than assembled, and it
is checkable rather than arguable: `test/brutal_surface_test.dart` asserts that
no `BoxShadow(` literal exists in `lib/` outside the two token files and that no
visible surface still resolves a soft elevation. A design that can be verified
by grep is worth more than a design that cannot.

### One derivation that still makes the whole system work

A down-right offset hard shadow shows only a thin sliver on the bottom and right
of a box. That sliver always sits on the **page surface** — `canvas` or `paper` —
never on the box's own fill. So the shadow token only ever has to clear 3:1
against the page surface, and is completely fill-agnostic. That is why one locked
shadow token works for every surface in the app, in both modes, on saturated
fills (`accentDeep`), light fills (`ink` in dark mode) and a near-black slab
(`codeBg`) alike.

**The derivation covers the shadow, and only the shadow.** A `BoxDecoration`
border paints *inside* the box, **on top of** `decoration.color`. So a focus
ring, a resting edge, and any label drawn on a fill are all scored against the
box's **own fill** — never against the page. An earlier version of this document
asserted the opposite for the ring (that it "never sits on the fill") and
concluded that one focus colour and one placement rule could serve every surface.
Both claims were false. §6.10 states the rule that replaced them; §7.1 carries
the arithmetic for both halves, and **§4.9–§4.16 apply that same rule to the
read-only surfaces** rather than inventing a parallel one.

---

## 2. Inventory of target surfaces

Counts are the **pre-migration** tree, read from `git show HEAD:<file>`. "Material button call site" = one `FilledButton` / `OutlinedButton` / `TextButton` (including `.icon` forms) used as a widget, not a theme declaration.

> **Line-reference convention.** Every `file:line` in §2 and §4 is a **pre-migration** position. §2 is an inventory of what the tree held before the migration, and those line numbers do not resolve in the working tree any more. A position in the tree **as built** is written the same way and marked "(post-migration)"; those appear only where the current position is load-bearing — §2.1's post-migration table and §7.6. The files introduced by this spec (`brutal_tokens.dart`, `brutal_button.dart`, `brutal_chip.dart`, `brutal_field.dart`, `brutal_activate.dart`) have no pre-migration position at all, so every reference to them is post-migration by default and is not marked.

### 2.1 Material button call sites — 29 migratable across 11 files

Read from `git show HEAD:<file>`. The per-file split is not read off the total row, which is what makes the three tables in this section reconcilable against each other.

| File | Filled | Outlined | Text | Lines (pre-migration) | Total |
|---|---|---|---|---|---|
| `lib/screens/home_screen.dart` | 3 | 0 | 1 | 678, 683, 747, 794 | 4 |
| `lib/screens/settings_screen.dart` | 3 | 0 | 4 | 888, 925, 929, 1026, 1030, 1153, 1157 | 7 |
| `lib/screens/detail_screen.dart` | 2 | 1 | 0 | 506, 524, 873 | 3 |
| `lib/screens/actions_history_screen.dart` | 1 | 0 | 1 | 367, 371 | 2 |
| `lib/screens/shopping_list_screen.dart` | 1 | 0 | 1 | 296, 300 | 2 |
| `lib/screens/chat_screen.dart` | 1 | 0 | 1 | 366, 370 | 2 |
| `lib/screens/onboarding_screen.dart` | 1 | 0 | 1 | 65, 107 | 2 |
| `lib/widgets/widgets.dart` | 1 | 0 | 1 | 264, 271 | 2 |
| `lib/widgets/chat_atoms.dart` | 0 | 1 | 1 | 458, 468 | 2 |
| `lib/widgets/privacy_gate.dart` | 1 | 0 | 1 | 25, 29 | 2 |
| `lib/widgets/about_dialog.dart` | 1 | 0 | 0 | 76 | 1 |
| **Total (migratable)** | **15** | **2** | **12** | | **29** |

> **Correction to the brief, and to an earlier version of this table.** The brief stated 26 call sites across 8 screens; the tree has **29 migratable across 11 files** (22 across 7 screen files, plus 7 in `lib/widgets/`). Migrate against this table, not the brief's number.

**The 30th site — the OCR copy button — was the one sanctioned exception, and it is no longer one.** `detail_screen.dart:324` (pre-migration) was a `TextButton` carrying a `style:` override, excluded by §2.5 as a "read-only mono block" exception. The §2.5 reversal retired it: it is now a `BrutalButton.outline` at height 36, and it is the **only** Material button left in the app at 0.

| | Filled | Outlined | Text | Total |
|---|---|---|---|---|
| Pre-migration, all call sites | 15 | 2 | 13 | 30 |
| Less the §2.5 OCR exception (as built) | −0 | −0 | −1 | −1 |
| **Migratable, as built** | **15** | **2** | **12** | **29** |
| Plus the OCR exception, after the reversal | +0 | +1 | −1 | **30 of 30** |

**Post-reversal tree state.** Line references in this table are post-migration.

| | Filled | Outlined | Text | `BrutalButton` |
|---|---|---|---|---|
| After the §2.5 reversal | **0** | **0** | **0** | **30** |
| Migrated | 15 → 0 | 2 → 0 | 13 → 0 | **30 of 30** |

Of the 30 `BrutalButton`s: 10 `filled`, 1 `destructive` (`settings_screen.dart:1030`), 3 `outline` (two `.icon` plus the OCR copy button), 12 `text`, 4 `.icon` filled. Every per-file row in the pre-migration table reconciles against that — the same 4 / 7 / 3 / 2 / 2 / 2 / 2 / 2 / 2 / 2 / 1 split — which is the check that the migration moved call sites and neither added nor dropped any. The tables reconcile in that order: 15 + 2 + 13 = **30** pre-migration, and the tree as built now contains exactly 30 `BrutalButton` call sites and **zero** Material buttons.

### 2.2 Text inputs — 5

| Site | Container | Current border | Current focus |
|---|---|---|---|
| `home_screen.dart:420` (library search) | `home_screen.dart:403-413` | `divider` @ `hairline` | `accent` @ 1.5 (`home_screen.dart:410-411`) |
| `chat_screen.dart:692` (composer) | `chat_screen.dart:680-691` | `divider` @ 1.0 | `accent` @ 1.5 (`chat_screen.dart:688-689`) |
| `detail_screen.dart:765` (add tag) | `detail_screen.dart:756-764` | `divider` @ `hairline` | none |
| `settings_screen.dart:674` (API key) | `settings_screen.dart:664-673` | `divider` @ `hairline` | none |
| `shopping_list_screen.dart:164` (add item) | `shopping_list.dart:154-163` | `divider` @ `hairline` | none |

All five are the same shape: a `Container` with a `BoxDecoration` wrapping a `TextField` whose own `InputBorder` is `none`. **The border lives on the container, not the field.** Migration therefore touches the container decoration only — no `InputDecoration` changes, no `TextField` changes.

### 2.3 Chips and selected filters — 3 widget classes

| Class | File:line | Current | Notes |
|---|---|---|---|
| `_filterChip` | `home_screen.dart:602-645` | `paper`/`accentSoft` fill, 0.5–1pt border, **32dp** in a 40dp slot (`:570`) | Includes an "All" chip plus one per tag |
| `_FilterChip` | `actions_history_screen.dart:387-431` | `surfaceWarm1`/`accentSoft` fill, **no border**, 32dp | Note: this one has no border at all today |
| `_PromptChip` | `chat_screen.dart:780-814` | `surfaceWarm1` fill, **no border**, 32dp | Example prompts and recent queries |

`TypeBadge` and `TagChip` are **not** in this list, because they are data labels, not controls. Since the §2.5 reversal they *are* hard-edged, but as labels rather than as chips: same 2pt edge and `rControl`, **no cast shadow**, and no focus or press machinery. §4.12 specifies them and says why the missing shadow is the thing that keeps them from looking pressable.

### 2.4 Switches — 1 helper, 3 call sites

`_flatSwitch` at `settings_screen.dart:828-833` is a one-line `Switch(value:, onChanged:)` wrapper, called at `settings_screen.dart:269` (auto-detect), `:303` (haptics), `:320` (local-only). `switchTheme` is at `app_theme.dart:646-656`.

### 2.5 Explicitly OUT of the brutal set

**Amended.** This table used to hold fourteen rows; **nine of them were
reversed** after the device review (§1), and **one more — the chat bubble — is
newly in scope**. Those ten are now specified in §4.9–§4.16 and are marked
**IN SCOPE** below. What remains is the current exclusion list, and every
remaining row is still a live constraint.

| Surface | File | Status |
|---|---|---|
| Screenshot cards | `home_screen.dart`, `skeleton.dart` | **IN SCOPE (reversed)** → §4.10 |
| `TypeBadge` | `widgets.dart` | **IN SCOPE (reversed)** → §4.12. Kept non-interactive: hard edge, no shadow. |
| `TagChip` body | `widgets.dart` | **IN SCOPE (reversed)** → §4.12. Its 40×40 delete target keeps its own ring (§4.6). |
| OCR block + copy button | `detail_screen.dart` | **IN SCOPE (reversed)** → §4.16. The copy button is now `BrutalButton.outline`; **the app has zero Material buttons.** |
| Snackbar | `app_theme.dart` | **IN SCOPE (reversed)** → §4.11 |
| Bottom-sheet chrome | `widgets/bottom_sheet.dart`, `app_theme.dart` | **IN SCOPE (reversed)** → §4.11 |
| Dialog chrome | `app_theme.dart` | **IN SCOPE (reversed)** → §4.11 |
| Processing / ingest / error banners | `widgets.dart`, `ingest_banner.dart`, `home_screen.dart` | **IN SCOPE (reversed)** → §4.13 |
| Skeletons | `skeleton.dart` | **IN SCOPE (reversed)** → §4.15. (Row separators and OCR **mono type** in the same old row did **not** reverse.) |
| ~~User chat bubble~~ | `chat_atoms.dart` | **IN SCOPE (new)** → §4.14. Never listed here before, and it was inconsistent the moment the bubble's neighbours hardened. |

**Still excluded, each with its reason unchanged:**

| Surface | File | Why it stays warm |
|---|---|---|
| Evidence-strip thumbnails | `chat_atoms.dart:161-251` | 48dp image boxes read at `cacheWidth: 96`. A 2pt edge there is 4% of the image and lands ON the photograph; the fill already separates them from the page. Bare image containers, not surfaces. |
| Circular icon buttons | `_CameraCircle`, `SiftSendCircle`, `_AddCircle`, `_AddItemCircle`, `_QuietCircle` | A hard cast shadow fights a circle's curvature. **Still honoured** — the shape exclusion over-reached onto FOCUS once and that was fixed in §7.7; it has not been fixed back. |
| `_ThemeSegmented` | `settings_screen.dart` | Its selected state is a *sliding thumb*. A hard shadow on a sliding thumb means animating a shadow. |
| `_flatRow`, `_infoRow`, `_linkRow`, `_FeatureRow`, `_licenseRow`, nav bar, evidence rows, related-link **rows** | `settings_screen.dart`, `app_shell.dart`, `chat_atoms.dart` | Tappable rows, but they are **navigation affordances inside a scroll of identical rows**. Brutalizing them turns a Settings list into a wall of hard edges — §6.2. They get a focus ring only. Note the asymmetry that this creates and that it is deliberate: the *container* is hard (§4.9), the *rows* inside it are not. |
| The assistant essay block | `chat_atoms.dart` `EssayBlock` | It is **bare text on the page** and stays that way. §4.16 explains why adding a bubble would be the one place the reversal should stop. |
| Photo overlays — the card's timestamp pill, `_QuietCircle` back/pin | `home_screen.dart`, `detail_screen.dart` | These sit ON a screenshot. A hard edge there competes with the image for attention and reads as part of the screenshot. |
| Status pills — the chat header's Local/Cloud chip, `_quietTag` ("Recommended") | `chat_screen.dart`, `settings_screen.dart` | Small status indicators whose whole job is a hue plus an icon. A 2pt edge on a 12pt-radius pill of `accentSoft` would be mostly border. Not containers. |
| **Row separators** — all 8 `Divider(...)` call sites | `actions_history_screen.dart:219,292`, `detail_screen.dart:282`, `onboarding_screen.dart:289,291`, `settings_screen.dart:502`, `shopping_list_screen.dart:226`, `about_dialog.dart:171` | Every one separates two rows of the **same table**. §4.15 argues this with the arithmetic. |
| Edge-to-edge screen rules — the nav bar's top border, the detail/shopping bars' top and left borders | `app_shell.dart:112`, `detail_screen.dart:479,507`, `shopping_list_screen.dart:64,146` | A 2pt line across the full width of a screen is a page border, not a component edge. |
| `EmptyState` chrome, all typography, `SiftSpacing` | — | §9. |

---

## 3. Token design

New tokens **extend** the existing system. No existing constant changes value. Two new hex values are introduced, both shadow composites (`Color(0x8C281E14)`, `Color(0x73E8E0D2)`); every colour token added after them is an alias of a step the palette already had — `stone`, `ink`, `canvas`, `onAccent`, `bone`, `accent`, `accentDeep`, `error`.

### 3.1 New file: `lib/theme/brutal_tokens.dart`

```dart
import 'package:flutter/material.dart';

/// Neobrutalism tokens.
///
/// SIFT is a warm-paper reading app, and this is now the app's surface language
/// rather than a control accent. The §1 rule that governed the first pass —
/// "brutalism marks what you can touch, warmth marks what you read" — was
/// REVERSED after a device review: brutal buttons were landing inside warm
/// containers and the user judged the remainder not to belong to them. The
/// grammar is now one system across every surface, interactive and read-only
/// alike. DESIGN-BRUTALIST.md §1 records the reversal and the reason; the
/// colour personality of the palette is unchanged, so the app still reads as
/// warm paper carrying hard edges.
///
/// Every value here is locked. Per-component overrides are a bug, not a
/// variation: two different shadow directions is the fastest way to make a
/// hard-edge language read as a rendering fault.
abstract final class SiftBrutal {
  SiftBrutal._();

  /// Control border weight. The existing hairline (0.5 light / 1.0 dark,
  /// AppTheme.hairline) is a *layer separator*; this is a *boundary marker* and
  /// needs enough weight to survive at 3:1 legibility against a light fill.
  /// 1.5 was tried and reads as a hairline at chip size.
  ///
  /// The control CORNER radius is deliberately NOT here. It lives once, as
  /// `SiftRadii.rControl`, and every brutal control that has a corner to round
  /// reads that name. Restating the value here is what would let one hard edge
  /// become two, and the absence of a second copy is the enforcement.
  static const double borderW = 2.0;

  /// The one hard shadow offset. Direction is down-right on the assumption of
  /// a top-left light source, which is also the direction the existing warm
  /// L1–L4 shadows assume (all positive-Y; only L5 is negative-Y, and L5 is
  /// not used on any control).
  static const Offset offset = Offset(4, 4);

  /// Light-mode hard shadow: the existing warm shadow base #281E14 at 55%.
  /// Alpha is chosen so the 4pt sliver clears WCAG 2.1 SC 1.4.11 (3:1
  /// non-text contrast) against BOTH light page surfaces:
  ///   canvas #F8F4ED → 3.64:1 · paper #FBF9F4 → 3.80:1
  /// Because the offset hides the near edges, this value is fill-agnostic: it
  /// works under an accentDeep fill and a paper fill alike. That is why there
  /// is no accent-coloured hard shadow anywhere in the system.
  static const List<BoxShadow> hardLight = [
    BoxShadow(color: Color(0x8C281E14), offset: Offset(4, 4), blurRadius: 0),
  ];

  /// Dark-mode hard shadow: the edge is INVERTED to a light value.
  ///
  /// A black hard shadow on canvas #1F1B16 is arithmetically invisible —
  /// contrast(black, #1F1B16) = 0.06133/0.05 = 1.23:1. The offset edge
  /// therefore becomes `ink` at 45%, chosen to clear 3:1 against all three
  /// dark surfaces a control can sit on AND against the dark filled button's
  /// own cream fill:
  ///   canvas #1F1B16 → 3.69:1 · paper #2A2520 → 3.27:1
  ///   dark FilledButton fill ink #E8E0D2 → 3.54:1
  static const List<BoxShadow> hardDark = [
    BoxShadow(color: Color(0x73E8E0D2), offset: Offset(4, 4), blurRadius: 0),
  ];

  static const List<BoxShadow> none = [];

  static List<BoxShadow> hard(bool isDark) => isDark ? hardDark : hardLight;

  /// Press: the control translates down-right by [offset] while the shadow
  /// collapses to zero offset. blurRadius stays 0 in both states — the shadow
  /// never softens, it only disappears.
  ///
  /// A 4pt translate is deliberate: it equals the shadow offset exactly, so
  /// the control lands precisely on its own shadow and the button appears to
  /// have been pushed into the page. A smaller translate leaves a visible
  /// gap; a larger one detaches it.
  static const List<BoxShadow> hardPressedLight = [
    BoxShadow(color: Color(0x8C281E14), offset: Offset.zero, blurRadius: 0),
  ];
  static const List<BoxShadow> hardPressedDark = [
    BoxShadow(color: Color(0x73E8E0D2), offset: Offset.zero, blurRadius: 0),
  ];

  static List<BoxShadow> hardPressed(bool isDark) =>
      isDark ? hardPressedDark : hardPressedLight;

  /// Focus-visible ring colour, light mode, ON A PAGE-FILLED CONTROL. NOT
  /// `accent`: accent on canvas is 2.85:1 and on paper 2.97:1 — both below the
  /// 3:1 non-text threshold, so the existing 1.5pt `accent` focus ring
  /// (app_theme.dart:589, :716) does not clear SC 1.4.11. `accentDeep` clears
  /// it with margin: 4.79:1 on canvas, 4.99:1 on paper. Thicker is not a
  /// substitute for a different hue; both changes are made.
  ///
  /// This is the ring for a control whose own box is a PAGE step — `paper`,
  /// `surfaceWarm1`, `surfaceWarm2`, or nothing at all on the ghost. A control
  /// that fills with a colour instead is a slab, and a slab cannot use this
  /// pair: see [focusOnFill].
  static const Color focusLight = Color(0xFFB04F2B); // == accentDeep

  /// Focus-visible ring colour, dark mode, on a page-filled control. `accent`
  /// clears 3:1 here (5.48:1 on canvas, 4.86:1 on paper) where `accentDeep`
  /// would not (3.26:1 on canvas, 2.89:1 on paper).
  static const Color focusDark = Color(0xFFD97757); // == accent

  static Color focus(bool isDark) => isDark ? focusDark : focusLight;

  /// The focus ring ON A FILLED SLAB — a filled or destructive button, the
  /// selected chip, the ON switch track. A slab is the one control whose own
  /// box is a colour rather than a page step.
  ///
  /// A `BoxDecoration` border paints INSIDE the box, ON TOP OF THE FILL, so the
  /// ring is always on the fill. On the light filled button the fill IS
  /// `accentDeep` and [focusLight] is also `accentDeep` — 1.00:1, no indicator
  /// at all (§6.10).
  ///
  /// A slab ring therefore cannot be a darker shade of the slab. It is the
  /// value the slab is never filled with — the control's own FOREGROUND, which
  /// every slab is already painting its label or thumb in, so this costs no new
  /// hue in either mode. One value per mode covers every slab fill, because
  /// the palette offers nothing else: the only light steps clear of
  /// `accentDeep` are `paper` / `onAccent` / `canvas` (4.79–4.99:1) and the
  /// only dark one clear of `ink` is `canvas`.
  ///
  ///   light  `onAccent` #FBF9F4 → accentDeep 4.99 · error 5.47 · ink 14.28
  ///   dark   `canvas`   #1F1B16 → ink 13.06 · error 6.10 · accentDeep 3.26
  ///
  /// [pressed] follows the press, which inverts the fill exactly as it
  /// inverts the label (§4.1): the dark press fill IS `canvas`, i.e. the dark
  /// ring, so a dark button held down while focused would show 1.00:1. The
  /// light pair needs no flip — `onAccent` is 14.28:1 on the light press fill.
  static const Color focusOnFillLight = Color(0xFFFBF9F4); // == onAccent
  static const Color focusOnFillDark = Color(0xFF1F1B16); // == canvas (dark)
  static const Color focusOnFillPressedDark =
      Color(0xFFE8E0D2); // == ink (dark)

  static Color focusOnFill({required bool isDark, bool pressed = false}) {
    if (!isDark) return focusOnFillLight;
    return pressed ? focusOnFillPressedDark : focusOnFillDark;
  }

  /// The RESTING 2pt edge on a filled slab. `stone` — the resting edge on
  /// every page-filled control — is arithmetically blind on a slab: 1.06:1 on
  /// the light `accentDeep` fill, 1.16:1 on `error` in both modes. The light
  /// filled button's border, the one the whole 2pt language rests on, drew
  /// nothing.
  ///
  /// `bone` is the one palette step that separates from every slab fill in both
  /// modes, and the one that maximises the worst case of the alternatives
  /// (`stone` 1.06, `graphite` 1.38, `ink` 1.00 — it IS the selected chip's
  /// fill — `error` 1.00).
  ///
  ///   light  accentDeep 2.32 · error 2.54 · ink 6.64 (selected chip, pressed)
  ///   dark   ink 6.08 · error 2.84 · canvas 2.15 (pressed)
  ///
  /// The cost of one shared value is that the ring sits 2.15:1 from it, so the
  /// focus state is a step rather than an inversion. A resting edge is not the
  /// focus indicator, so SC 1.4.11's 3:1 is not owed here; what it owes is
  /// being visible, and 2.15:1 where the defect was 1.06:1 is.
  static const Color edgeOnFillLight = Color(0xFFB5AB9E); // == bone (light)
  static const Color edgeOnFillDark = Color(0xFF5A4F44); // == bone (dark)

  static Color edgeOnFill(bool isDark) =>
      isDark ? edgeOnFillDark : edgeOnFillLight;

  /// RESTING 2pt edge on a hard-edged READ-ONLY surface: the card, the
  /// dialog and sheet boxes, the chat bubble, the badge, the tag, the banners,
  /// the skeleton, and the OCR block.
  ///
  /// This is `stone`, already the resting edge on every page-filled
  /// interactive control, so the §2.5 reversal cost no new colour in either
  /// mode. The old edge could not be kept for the same reason the control edge
  /// could not: a `BoxDecoration` border is painted on top of the fill, so the
  /// card's 1pt `divider` was 1.42:1 light / 1.22:1 dark on a box that is an
  /// `InkWell`.
  ///
  ///   light  paper 4.72 · canvas 4.53 · surfaceWarm1 4.15 · surfaceWarm2 3.79
  ///         · errorSoft 3.90 · codeBg 3.45  <- the OCR block, tightest row
  ///   dark   paper/surfaceWarm1 4.68 · canvas 5.28 · surfaceWarm2 3.83
  ///         · errorSoft 3.78 · codeBg 5.74
  static const Color surfaceEdgeLight = Color(0xFF7A6E61); // == stone (light)
  static const Color surfaceEdgeDark = Color(0xFF998D80); // == stone (dark)

  static Color surfaceEdge(bool isDark) =>
      isDark ? surfaceEdgeDark : surfaceEdgeLight;

  /// Press timing. Mirrors MotionTokens.press / MotionTokens.pressRelease
  /// rather than restating them, so the brutal press obeys the app's single
  /// reduced-motion gate for free: under reduced motion both durations
  /// collapse to Duration.zero and the press becomes an instant state swap.
  static Duration get pressIn => MotionTokens.press;

  static Duration get pressOut => MotionTokens.pressRelease;
}
```

`brutal_tokens.dart` imports `motion_tokens.dart` and nothing else. The control radius lives in exactly one place — `SiftRadii.rControl` — and `SiftBrutal` has **no** `radius` constant. Every hard-edged surface that has a corner to round reads that one name: `BrutalButton`, `SiftBrutalChip`, `BrutalField`, the sheet's `_SourceOption`, and — since the §2.5 reversal — the card, dialog, sheet chrome, snackbar, chat bubble, badge, tag, banners, skeleton and OCR block. The two hard-edged surfaces without a corner are `TagChip`'s 40pt delete target and the chat send circle, and both are `BoxShape.circle`, so neither has a corner radius to set. A second copy of the value is how one hard edge becomes two, so the absence is the enforcement.

**The four values a read-only surface needs are built in one function, not sixteen.** `brutalEdge(...)` lives in `brutal_chip.dart` beside `SiftBrutalChip` — beside it deliberately, because the reason a pill cannot carry this border (§4.6) is the reason the labels belong in the same file. It takes `fill`, `isDark`, and optional `border` / `shadow` / `borderRadius` overrides, and returns the `BoxDecoration` for a `rControl` corner, the 2pt edge and the hard shadow. `SiftBrutalChip` is its first caller, passing both overrides because it has focus, press and disabled branches. The rest — `TypeBadge`, `TagChip`, `_RecognitionChip`, `_SiftCard`, `ScreenshotCardSkeleton`, `ProcessingBanner`, `IngestBanner`, the home error banner, the home batch bar, the home Ask bar, Detail's web-result tile, the OCR block, `UserPill`, `RelatedLinksStrip`, the onboarding mock panel, `PremiumBottomSheet` — take the defaults.

```dart
// In SiftRadii. Interactive surfaces AND read-only surfaces; the values below
// it are unchanged and remain correct for what still uses them.
/// The one hard-edged radius: buttons, inputs, chips, sheet options, and — since
/// the §2.5 reversal — cards, dialogs, sheets, snackbars, chat bubbles, badges,
/// tags, banners, skeletons and the OCR block.
static const double rControl = 4;
```

**Two figures inside the listing above are stale, in the file as well as here.** `hardLight`'s comment quotes `paper #FBF9F4 → 3.80:1` and `hardDark`'s quotes `paper #2A2520 → 3.27:1`; both were computed against the wrong composite. The measured values are **3.67:1** and **3.54:1** (§7.1). No token value is affected — only the two prose figures in the doc comments. Left in place because this listing reproduces `brutal_tokens.dart` as it is; corrected there, they would be corrected here too.

### 3.2 What this does NOT touch

**Amended for the §2.5 reversal.** The original list said "interactive surfaces
only". It no longer says that. What is still true, and load-bearing:

- **Serif families.** `SiftType.serifFamily = 'SourceSerif4'` and every
  `serif*` role are unchanged. **The assistant voice is the product** — §4.16 is
  the surface where the reversal stops rather than continue, precisely so this
  stays true.
- **Canvas / paper / surface colours.** `SiftColors.canvas`, `paper`,
  `surfaceWarm1`, `surfaceWarm2` are unchanged in both `light` and `dark`.
  **No read-only surface in §4.9–§4.16 changed its fill.** Every contrast figure
  in §7.1 that concerns body text is therefore carried over unchanged, and the
  only new numbers are for the EDGES — which is why the work could be done
  without re-auditing any copy.
- **The accent itself.** `accent #D97757` is unchanged. `accentDeep #B04F2B` is
  unchanged. `accentSoft` is unchanged. `accentPressed #BE6242` stays in the
  palette but is retired for brutal buttons (§4.1 explains why).
- **Soft shadow levels L1–L5 and `l4Dark`.** Untouched, alpha and offset
  unchanged, and §9 forbids removing them — they are the ramp for non-surface
  work. **What changed is that no visible surface reads them any more**;
  `test/brutal_surface_test.dart` asserts that too. `SiftElevation.card()` and
  `SiftElevation.sheet()` are kept as superseded helpers, not deleted, with
  comments saying so.
- **`SiftSpacing`.** No spacing value changes. See §6.5 for the touch-target
  reasoning that this implies.
- **`AppTheme.hairline(isDark)`.** Unchanged at 0.5 / 1.0, and still read by the
  screen-edge rules, the row separators, and the surfaces §2.5 still excludes.
- **Every radius except `rControl`.** `rCard 20`, `rSheet 24`, `rThumb 12`,
  `rField 16`, `rInline 4` and the 999 pills are all unchanged as tokens. What
  changed is that `rCard`, `rSheet` and `rField` now have far fewer callers:
  `rCard` has **none**, `rSheet` has **none**, and `rField` survives only on
  `_flatRow` / `_infoRow` / `_linkRow` in Settings, which are §2.5 exclusions.
- **No new hex outside `app_theme.dart` / `brutal_tokens.dart`.** The colours
  introduced by the reversal are `surfaceEdgeLight/Dark`, and both are aliases of
  `SiftColors.stone`, which both instances already had — the same pattern as
  `edgeOnFill` → `bone` and `edgeOnTrack` → `divider` / `ink`. The only true
  literals remain `Color(0x8C281E14)` and `Color(0x73E8E0D2)`. This preserves
  the invariant recorded in DESIGNSTATE.md:128 ("all hexes in app_theme.dart") in
  spirit — `brutal_tokens.dart` is the second sanctioned home.
- **No copy.** Not one runtime string literal changed. See §6.9.

---

## 4. Per-surface specification

Conventions used throughout:

- `B` = `SiftBrutal.borderW` = 2
- `O` = `SiftBrutal.offset` = `Offset(4, 4)`
- `HL` / `HD` = `hardLight` / `hardDark`
- `F` = focus colour on a **page step** (`focusLight` / `focusDark`)
- `F'` = focus colour on a **slab** (`focusOnFillLight` / `focusOnFillDark`, plus `focusOnFillPressedDark` for a dark button held down while focused)
- `E` = resting edge on a **slab** (`edgeOnFillLight` / `edgeOnFillDark`)
- **Page step vs slab.** A `BoxDecoration` border paints inside the box, on top of the fill, so a control's own box is what its edge is scored against. A box filled with `paper` / `surfaceWarm1` / `surfaceWarm2` / `surfaceWarm2` / nothing is a **page step** and keeps `stone` at rest and `F` on focus. A box filled with `accentDeep`, `error` or `ink` is a **slab** and takes `E` at rest and `F'` on focus. A disabled control is never a slab — `surfaceWarm2` is a page step even on the `filled` variant. The rule, the arithmetic and the false claim it replaces are in §6.10.
- `isDark` is `Theme.of(context).brightness == Brightness.dark`, the pattern used at `app_theme.dart:465` and every call site in §2.
- "rest" shadow = `SiftBrutal.hard(isDark)`; "pressed" shadow = `SiftBrutal.hardPressed(isDark)`.

### 4.0 Hover — a deliberate no-op, for every surface

**Hover produces no visual change on any surface in this spec.** The app sets `hoverColor: Colors.transparent` and `highlightColor: Colors.transparent` globally (`app_theme.dart:587-589`) and has no pointer-device UI to serve. Adding hover feedback would be animation beyond the press translation (§9) and would make a mouse feel different from a finger for no product reason.

Implementers: do not add a hover branch. If a platform later needs one, it is a new spec, not a parameter here.

### 4.1 Filled button — `BrutalButton` (`BrutalButton.icon`)

| State | Fill | Label | Border | Shadow | Translate |
|---|---|---|---|---|---|
| rest | `accentDeep` (light) / `ink` (dark) | `onAccent` (light) / `canvas` (dark) | `E` @ B | HL / HD | `Offset.zero` |
| hover | — no change — | | | | |
| **pressed** | **`ink` (light) / `canvas` (dark)** | **`canvas` (light) / `ink` (dark)** | `E` @ B | HL/HD @ `Offset.zero`, blur 0 | `O` |
| focus-visible | as rest | as rest | **`F'` @ B** (replaces the edge) | as rest | `Offset.zero` |
| disabled | `surfaceWarm2` | `stone` | `stone` @ B | `none` | `Offset.zero` |

Notes for the implementer:

- **This variant's box is a slab, so it never uses `stone` or `F`.** `accentDeep` and `ink` are colours, not page steps, and the 2pt border is painted on top of them. The resting edge is `E` and the ring is `F'`. The disabled row is the exception that proves the rule: `surfaceWarm2` is a page step, so a disabled filled button goes back to `stone`.

- **The pressed fill is a full inversion, not a tint.** The app's existing press fill is `accentPressed #BE6242`, whose contrast with `onAccent #FBF9F4` is **3.98:1** — it fails SC 1.4.3 (4.5:1) for a 15pt/600 label, so the existing pressed state is a genuine contrast regression that this spec removes by construction. `ink` on `accentDeep` is 4.99:1; `canvas` on `ink` (dark) is 13.06:1.
- **The inversion is also the reduced-motion co-signal.** A fill flip is a 0ms state change, so when `MotionTokens.enabled` is false (§6.6) the press is still unmistakable without the translate.
- **Disabled keeps its border but loses its shadow.** A shadow means "this is available." `stone` on `surfaceWarm2` is 3.79:1, which clears the 3:1 non-text threshold for the control's shape. The disabled *label* is 3.79:1 and therefore does **not** meet 4.5:1 — that is conformant, because SC 1.4.3 explicitly exempts text in inactive components. Do not "fix" it.
- **Focus does not add a second ring.** See §5.4.

### 4.2 Outlined button — `BrutalButton.outline` (`.outline.icon`)

| State | Fill | Label | Border | Shadow | Translate |
|---|---|---|---|---|---|
| rest | `paper` | `ink` | `stone` @ B | HL / HD | `Offset.zero` |
| hover | — no change — | | | | |
| pressed | `surfaceWarm1` (light) / `surfaceWarm2` (dark) | `ink` | `stone` @ B | HL/HD @ `Offset.zero` | `O` |
| focus-visible | as rest | as rest | `F` @ B | as rest | `Offset.zero` |
| disabled | `paper` | `stone` | `stone` @ B | `none` | `Offset.zero` |

The dark pressed fill must be `surfaceWarm2`, not `surfaceWarm1`: in `SiftColors.dark`, `surfaceWarm1` and `paper` are the same value (`#2A2520`, `app_theme.dart:318-319`), so `surfaceWarm1` would be an invisible no-op in dark mode.

### 4.3 Text button — `BrutalButton.text` (`.text.icon`)

| State | Fill | Label | Border | Shadow |
|---|---|---|---|---|
| rest | none | `ink` | none | none |
| pressed | `surfaceWarm1` (light) / `surfaceWarm2` (dark) | `accentDeep` (light) / `accent` (dark) | none | none |
| focus-visible | none | as rest | `F` @ B | none |
| disabled | none | `stone` | none | none |

**Ghost buttons get no hard shadow, and this is load-bearing, not an oversight.** A down-right offset shadow needs a silhouette to cast from. Giving a ghost button a shadow means giving it a fill, which promotes a quiet secondary action ("Skip", "Not now", "Clear", "Copy") to primary visual weight and floods the app with hard edges — the §6.2 failure.

The accepted cost: ghost buttons are the one interactive class that does not carry the mark, so the grammar has a hole. §6.2 records the one-line escape hatch if Phase 1 review finds the hole too wide.

### 4.4 Destructive button — `BrutalButton.destructive`

| State | Fill (light) | Fill (dark) | Label (light) | Label (dark) | Border | Shadow |
|---|---|---|---|---|---|---|
| rest | `error` | `error` | `onAccent` | `canvas` | `E` @ B | HL / HD |
| pressed | `ink` | `canvas` | `canvas` | `ink` | `E` @ B | HL/HD @ `Offset.zero` |
| focus-visible | as rest | as rest | as rest | as rest | `F'` @ B | as rest |
| disabled | `surfaceWarm2` | `surfaceWarm2` | `stone` | `stone` | `stone` @ B | `none` |

- `onAccent` on `error` (light) = **5.47:1** ✓. `canvas` on `error` (dark) = **6.10:1** ✓. Both follow the existing `onError` mode split at `app_theme.dart:482`.
- `error` is a slab, so this variant takes the same inverted edge pair as §4.1 — `E` at rest, `F'` on focus, in every state including pressed. One `error` fill, one ring: 5.47:1 light.
- The hard shadow is the same locked token. It is warm-black in light mode, so it is hue-independent and needs no `error` variant — this is the practical payoff of the §1 derivation.
- **Rollout scope for this variant: exactly one call site.** `settings_screen.dart:1030` ("Delete everything") — the only irreversible, unrecoverable action in the app. Every other confirm (`actions_history_screen.dart:371` "Clear all", `shopping_list_screen.dart:300` "Delete", `chat_screen.dart:370` "Clear", `settings_screen.dart:929` "Remove", `:1157` "Index library", `privacy_gate.dart:29` "Continue") stays on `BrutalButton` with the normal fill. Flooding the app with error-red slabs would spend the one semantic color DESIGNSTATE wants rare.

### 4.5 Text input — `SiftBrutalField`

| State | Fill | Border | Shadow | Label/hint |
|---|---|---|---|---|
| rest | `paper` | `stone` @ B | HL / HD | ink / `stone` hint |
| **focused** | `paper` | **`F` @ B** | **HL / HD (unchanged)** | ink / `stone` hint |
| disabled | `surfaceWarm2` | `stone` @ B | `none` | `stone` |

- **Radius `rControl` (4)**, replacing `SiftRadii.rField`.
- **The shadow does not change on focus.** A button's shadow collapses because a button *sinks*. Focus is not a sink — it is engagement — and a field that lost its shadow on focus would read as deflated. Only the border colour changes. This is a deliberate asymmetry with §4.1 and it is intentional.
- `F` replaces `accent` as the focus colour. `accent` on `paper` is 2.97:1 and on `canvas` 2.85:1 — the existing focus rings at `home_screen.dart:410`, `chat_screen.dart:688` do not clear 3:1. `focusLight` (4.99 / 4.79) does.
- Three of the five sites (`detail_screen.dart:765`, `settings_screen.dart:674`, `shopping_list_screen.dart:164`) have no focus border today. They gain one, which is an accessibility improvement, not just a restyle.
- The three focusable containers with no `FocusNode` (detail, settings key, shopping) get their focus state from a `Focus` widget wrapping the `Container` — do **not** add a `FocusNode` to the `TextField` plumbing.
- Height is unchanged: 48 (`settings_screen.dart:665`), 52 (`chat_screen.dart:683`, `shopping_list_screen.dart:155`), and intrinsic for search/tag fields. The 2pt border is drawn inside the existing bounds; the total height does not move.

### 4.6 Chip / filter / prompt chip — `SiftBrutalChip`

| State | Fill | Label | Border | Shadow | Translate |
|---|---|---|---|---|---|
| rest, unselected | `paper` (`home_screen.dart`) / `surfaceWarm1` (`actions_history`, `chat_screen`) | `tagText` / `ink` | `stone` @ B | HL / HD | `Offset.zero` |
| **selected** | **`ink`** | **`canvas`** | `E` @ B | HL / HD | `Offset.zero` |
| hover | — no change — | | | | |
| pressed | as rest/selected | as rest/selected | as rest/selected | HL/HD @ `Offset.zero` | `O` |
| focus-visible | as rest/selected | as rest/selected | `F` unselected / **`F'`** selected @ B | as rest/selected | `Offset.zero` |
| disabled | `surfaceWarm2` | `stone` | `stone` @ B | `none` | `Offset.zero` |

- **Radius `rControl` (4), replacing `BorderRadius.circular(999)`.** A full pill with a 2pt border and a down-right shadow produces a non-orthogonal intersection on the pill's curved leading edge where the border meets the shadow sliver; at 4pt the geometry matches the buttons. Judgement call, stated as such.
- **Selected = fill inversion to `ink`, never a label change.** The label is `canvas` in both modes, so "what is currently filtered" is carried by the fill and the label alone. That single rule is what prevents the three chip classes from each inventing its own selected look.
- **The border does move, and only because the border is painted on the fill.** The selected `ink` fill is a slab, so it takes `E` at rest and `F'` on focus; the unselected chip fills with a page step and keeps `stone` + `F`. The press never changes the chip's fill, so the ring has no press term here. Old `stone`-on-selected-`ink` measured 3.03:1 in light and would have been fine — the defect was the ring (2.86:1 in light, 2.38:1 in dark), and carrying the edge through the same rule is what keeps one control from having two border vocabularies. `E` on the selected fill is 6.64:1 light / 6.08:1 dark.
- **32dp chips and the 4dp translate.** `home_screen.dart:568-575` wraps the 32dp chip in a `SizedBox(height: 40)` and centres it, leaving exactly 4dp of slack above and below — the translate fits without overflow. Verify this at build time; it is the one place the chip translate can clip.
- `actions_history_screen.dart:387-431` and `chat_screen.dart:780-814` have **no border today**. Adding the 2pt border grows each chip by 4px total in each dimension. Both sit in wrapping/clipped rows; confirm no row reflows in Phase 3 review.
- `TagChip`'s 40×40 delete target (`widgets.dart`) gets a focus ring of `F` @ B and nothing else. **Superseded in part by the §2.5 reversal:** its pill body is now hard-edged too, as a *label* — `rControl`, 2pt `surfaceEdge`, and deliberately **no shadow** (§4.12). The target itself is unchanged: a `BoxShape.circle` carries no radius to set, and its own box has no fill, so the ring is scored against the `paper` pill beneath it — a page step, hence `F` and not `F'`.

### 4.7 Switch — `switchTheme` only, no new widget

| State | Track fill | Track outline | Thumb |
|---|---|---|---|
| rest, off | `surfaceWarm2` | **`stone` @ `trackOutlineWidth: 2`** | `ink` (light) / **`stone`** (dark) |
| selected, on | `accentDeep` | `stone` @ 2 | `paper` (light) / **`canvas`** (dark) |
| hover | — no change — | | |
| pressed | — no change — | | |
| focus-visible | as rest | `F` off @ 2 / **`F'` on** @ 2 | as rest |
| disabled | `surfaceWarm2` | `stone` @ 2 | `bone` |

```dart
switchTheme: SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? (isDark ? s.canvas : s.paper)
        : (isDark ? s.stone : s.ink),
  ),
  trackColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? s.accentDeep
        : s.surfaceWarm2,
  ),
  // The outline is painted inside the track, on top of the track FILL, so it is
  // scored against the track and not the page — the same rule the brutal
  // controls follow. The ON track fills with `accentDeep`, where `focus`
  // measures 1.00:1 in light and 1.68:1 in dark, so a selected AND focused
  // track takes the slab ring instead (§6.10). The off track is a
  // `surfaceWarm2` page step and keeps `focus`.
  trackOutlineColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? (states.contains(WidgetState.selected)
            ? SiftBrutal.focusOnFill(isDark: isDark)
            : SiftBrutal.focus(isDark))
        : s.stone,
  ),
  trackOutlineWidth: const WidgetStatePropertyAll(SiftBrutal.borderW),
),
```

**VERIFIED:** `SwitchThemeData.trackOutlineColor` and `trackOutlineWidth` both exist in the current Flutter API (fetched from `api.flutter.dev`, which tracks stable). A 2pt hard track outline is reachable without a custom widget.

Four things this fixes, all arithmetic:

- The track outline is currently `Colors.transparent` (`app_theme.dart:655`). `surfaceWarm2` on `canvas` is 1.22:1 in dark — the switch has no boundary at all today.
- The dark **unselected** thumb must change from `paper` to `stone`. `paper` on `surfaceWarm2` in dark is **1.22:1** — the thumb is currently invisible against its own track until the switch is turned on. `stone` on `surfaceWarm2` is **3.83:1** ✓.
- The dark **selected** thumb must change from `paper` to `canvas`. `paper` on `accentDeep` is 2.89:1, a hair under 3:1. `canvas` on `accentDeep` is **3.26:1** ✓.
- The **focused ON track** takes the slab ring, not `focus`. A focused-and-selected track is the one place a Material theme has to branch on two states at once, because the ON track is the app's only slab that is not a `BrutalButton` or a `SiftBrutalChip`. 4.99:1 light, 3.26:1 dark — §6.10. The **resting** ON outline is still `stone` and still under 3:1 on `accentDeep`; that is a known gap, not an oversight, and §7.6 records it.

**No hard shadow on the switch.** A thumb that slides along a track must not carry a cast shadow; the shadow would travel with it and the track would read as two overlapping objects. The 2pt outline carries the boundary instead.

**Radius is not controllable.** `SwitchThemeData` has no track-radius token; the track is a stadium. Documented exclusion, not a gap.

**No press translate.** The 4dp slide is the affordance; a 4dp drop on top of it is noise.

**Touch target.** Material's `Switch` is ≥48dp tall by default; `materialTapTargetSize` is left at its default. Do not shrink it.

### 4.8 Filled-button `maximumSize` interaction — read before implementing

`app_theme.dart:660` sets `maximumSize: Size.fromHeight(48)`. Under Material, `shape`'s border is painted *inside* the widget's bounds, so a 2pt border at height 48 leaves a 44dp interior. That is above Material's 40dp minimum and preserves the 48dp touch target exactly. No `maximumSize` change is needed and none should be made.

The one thing to watch: `BrutalButton` is a custom widget, so the theme's `maximumSize` no longer applies to it. `BrutalButton` must therefore set its own `height: SiftSpacing.btnH` (48) for the default filled/outlined variants and must not read `maximumSize` from the theme. `textButtonTheme` currently sets `minimumSize: Size(0, 40)` (`app_theme.dart:724`); `BrutalButton.text` should match at 40 to keep the 12 ghost call sites' row heights identical.

---

### 4.9 Read-only containers — the shared contract

Every surface in §4.10 through §4.16 is built by `brutalEdge(...)` and obeys this
table. It is stated once because it is true once.

| | Fill | Border | Shadow | Press / focus |
|---|---|---|---|---|
| Read-only surface | unchanged | `surfaceEdge(isDark)` @ B | `hard(isDark)` | **none** |
| Read-only **label** (§4.12) | unchanged | `surfaceEdge(isDark)` @ B | **`none`** | **none** |

The two things that are *not* state-dependent, and why:

- **The edge is scored against the surface's own fill, never the page.** A
  `BoxDecoration` border paints inside the box on top of `decoration.color`, so
  `surfaceEdge` had to clear 3:1 against every fill these surfaces actually
  use. It does, in both modes, on the tightest row being the OCR block at
  **3.45:1** (§7.1). The edge it replaced was `divider` at 1.42:1 / 1.22:1 — and
  the card was an `InkWell`, so that was a live SC 1.4.11 failure, not a
  preference.
- **No press, no focus, no translate.** None of these surfaces is operable. The
  focus machinery is not repeated here because there is nothing to focus: the
  one focusable thing inside a read-only surface — the OCR copy button, the tag
  delete target, the `_SourceOption` tiles, the Licenses row — is a **control**
  and is specified in §4.1–§4.7.

**Layout is untouched, and that is not luck.** A corner radius does not
participate in layout, and `Border.all` paints inside the existing bounds, so no
box changes size. The one exception is a chip that previously had **no** border
and grew by 4px per axis when it got one — already noted in §4.6 — and none of
the surfaces here was in that position except `TypeBadge` / `TagChip`, whose
padding already left room for a 2pt border inside their existing bounds.

### 4.10 Cards — `_SiftCard`, `ScreenshotCardSkeleton`, `cardTheme`

| | Fill | Border | Shadow | Radius |
|---|---|---|---|---|
| card at rest | `paper` (unchanged) | `surfaceEdge` @ B | `hard(isDark)` | `rControl` |
| card selected (selection mode) | `paper` | **`accent`** @ B | `hard(isDark)` | `rControl` |

**Before → after:** `rCard 20` → `rControl 4`; `divider` @ 1 → `surfaceEdge` @
2; `SiftElevation.card(isDark)` (L1 light, none in dark) → `hard(isDark)`.

Two decisions worth defending:

- **The selected border keeps the `accent` hue and only takes the weight.** It
  measured 2.97:1 on `paper` in light and 4.86:1 in dark before and after —
  thickness is not contrast — and selection is not carried by that border
  anyway: the barrier scrim over the image and the accent check badge both
  appear with it. Spending a new selection colour to move 0.03:1 would have been
  a palette change dressed as a restyle, and §9 forbids that.
- **`cardTheme` carries no hard shadow, and that is not an oversight.** Nothing
  in the app mounts a `Card`; `_SiftCard` and `ScreenshotCardSkeleton` are
  `Container`s and get the real `boxShadow`. `cardTheme` is the fallback for a
  future `Card`, and `Card` has no `boxShadow` — so on a `Card` this language is
  a border and a radius only. Its `elevation: 0` is load-bearing: a `Card` paints
  its shadow through Material's `elevation`, and Material elevation always blurs
  (§5.1), so leaving it on would put a soft Gaussian under a 2pt hard border.

### 4.11 Dialogs, sheets, snackbars — theme chrome

| | Fill | Border | Corner | Shadow |
|---|---|---|---|---|
| `dialogTheme` | `paper` (unchanged) | `surfaceEdge` @ B | `rControl` | **none** — `elevation: 0` |
| `bottomSheetTheme` | `paper` (unchanged) | `surfaceEdge` @ B | `rControl`, **top corners only** | none — `elevation: 0` |
| `PremiumBottomSheet` chrome | `paper` (unchanged) | `surfaceEdge` @ B | `rControl`, top corners only | **`hard(isDark)`** |
| `snackBarTheme` | `ink` (unchanged) | **`edgeOnFill`** @ B | `rControl` | none — `elevation: 0` |

**Before → after:** dialog `rCard 20` + no side → `rControl 4` + `surfaceEdge` @
2, and the M3 default `elevation: 6` **removed**; sheet chrome `rSheet 24` +
`SiftElevation.sheet` → `rControl 4` + `surfaceEdge` @ 2 + `hard`; snackbar
`rThumb 12` + no side → `rControl 4` + `edgeOnFill` @ 2.

Three things here are load-bearing and one is a **reported gap**:

1. **The snackbar takes the SLAB edge, not `surfaceEdge`.** It fills with `ink`
   in **both** modes, which is one of the four fills §6.10 defines a slab as, so
   the border is scored against `ink`: `edgeOnFill` (`bone`) is **6.64:1** light
   and **6.08:1** dark. The page-step `surfaceEdge` would have been 3.03:1 light
   and **0.40:1** dark — in dark mode this box is a cream `ink` fill and `stone`
   is a mid-warm grey, so the border would have been arithmetically absent. One
   line of state, resolved by the same rule as the controls, not a new one.
2. **The sheet rounds its top corners only.** It is flush with the bottom of the
   screen; rounding all four would show the modal barrier through four 4px
   notches. That is the reason `brutalEdge` takes a `borderRadius` override
   rather than a `double`.
3. **Removing `elevation` is the substantive part of the dialog change.**
   `Dialog`/`AlertDialog`/`SnackBar` paint their shape through a `Material`, and
   a `Material`'s only shadow is the blurred `elevation` one. Those boxes shipped
   with a soft 24px-blur shadow; leaving it under a 2pt hard border would put two
   shadow languages in the app, one of them a different direction — §6.3.
4. **GAP, reported rather than papered over: a dialog gets NO hard offset
   shadow.** The same Material wall is why §5.1 had to build `BrutalButton` from
   scratch, and it holds for `Dialog`: a `Material` cannot take a `boxShadow`.
   Getting one would mean hand-painting it at each of the eight `AlertDialog`
   call sites, which is the "29 chances to get the gutter wrong" problem §5.1
   already rejected for buttons — and unlike buttons, the `Dialog` box's own
   `Material` would still draw over the wrapper. **The dialog therefore carries
   a 2pt edge, a 4pt corner and no shadow, and that is the state that shipped.**
   `PremiumBottomSheet` gets its real shadow because it is a `Container`, not a
   themed `BottomSheet`. A reviewer who wants the dialog shadow has one option
   and no others: a shared wrapper widget applied to all eight sites, which is a
   new spec, not a local patch.

### 4.12 Labels — `TypeBadge`, `TagChip`, `_RecognitionChip`

| | Fill | Border | Corner | Shadow | Focus / press |
|---|---|---|---|---|---|
| label at rest | unchanged (`badgeBg` / `paper` / `surfaceWarm1`) | `surfaceEdge` @ B | `rControl` | **none** | **none** |

**Before → after:** 999-radius pill, no border (badge) or a 1pt `tagBorder`
hairline (tag) → `rControl` 4 with the 2pt `surfaceEdge`.

**The missing shadow is the whole design of this row.** A hard offset shadow
needs a silhouette to cast from, and it is what makes a hard box read as an
extruded object — that is, as something you can press. A label that casts would
be indistinguishable from an unselected `SiftBrutalChip` at a glance. §4.3
already established the principle for ghost buttons ("giving a ghost a shadow
means giving it a fill, which promotes a quiet secondary action to primary
visual weight"); §4.12 applies the same reasoning one step further down, to
something that is not a control at all. `brutal_chip_test`-style parity is
asserted directly: the label and the chip share a radius and a border width and
differ **only** in shadow.

`TagChip`'s 40×40 delete target is unaffected — it is a `BoxShape.circle`
control with its own ring (§4.6), and §4.12 is about the body.

### 4.13 Banners — `ProcessingBanner`, `IngestBanner`, the home error banner

| | Fill | Border | Corner | Shadow |
|---|---|---|---|---|
| processing | `surfaceWarm2` (unchanged) | `surfaceEdge` @ B | `rControl` | `hard(isDark)` |
| ingest, running | `surfaceWarm2` (unchanged) | `surfaceEdge` @ B | `rControl` | `hard(isDark)` |
| ingest, **paused** | `surfaceWarm1` (unchanged) | `surfaceEdge` @ B | `rControl` | `hard(isDark)` |
| error | `errorSoft` (unchanged) | `surfaceEdge` @ B | `rControl` | `hard(isDark)` |

**Before → after:** `rThumb 12`, no border, no shadow → `rControl` 4 + 2pt +
`hard`. The paused state steps the fill down one step rather than recolouring
the edge, so the edge keeps 3.79:1 light / 3.83:1 dark in both states.

The home error banner was not on the original list but is the same class of
surface as the two banners next to it; leaving it soft would have been the
§6.1 incoherence on the very screen the reversal was about. It is called out in
§10 so a reviewer can see it was a decision rather than a drift.

**Both animated affordances survive untouched:** `PulsingMark`'s 1.0 → 1.15
pulse and each banner's dismiss / pause-resume `IconButton` keep their tap
target and their callback. The banner has no hover or press state of its own —
it is not operable.

### 4.14 Chat bubbles — `UserPill`

| | Fill | Border | Corner | Shadow |
|---|---|---|---|---|
| user turn | `surfaceWarm1` (unchanged) | `surfaceEdge` @ B | `rControl` | `hard(isDark)` |

**Before → after:** 999-radius capsule, no border, no shadow → `rControl` 4 + 2pt
+ `hard`. Alignment (right), max width (80%), padding (16/10) and the 300ms
entrance slide are unchanged.

**The assistant side was NOT given a bubble, and that is the decision a reviewer
should check first.** `EssayBlock` remains bare serif text on the page. Two
arguments, and they point the same way:

1. **The distinction is already structural, and hardening the user side did not
   weaken it.** The user turn has a box; the assistant turn has none. That is a
   difference in *presence*, not in hue, and it survives a colour-blind reader, a
   greyscale screenshot and a dark-mode render identically. Adding a matching
   bubble to the assistant would have replaced a structural difference with a
   symmetric pair that only fill could still separate — strictly worse.
2. **The serif voice has no container in DESIGNSTATE.md and still has none.**
   §9 protects the typography; §4.16's whole content is that protecting the
   voice and the boxed bubble are the same decision taken twice.

`RelatedLinksStrip`, the assistant's one card-like container, **was** given the
hard edge (§4.9's shared contract) — it is a container, not text. Its individual
link rows stay soft, for the §2.5 reason.

### 4.15 Skeletons and row separators

**Skeleton.** `ScreenshotCardSkeleton` now resolves the *same* `brutalEdge(...)`
call as `_SiftCard`: `rControl` 4, `surfaceEdge` @ 2, `hard(isDark)`. Before:
`rCard 20`, a `divider` hairline, `SiftElevation.card(isDark)`. This is not
cosmetic — a skeleton at the old radius while the real card lands at 4pt is a
visible pop at the exact moment data arrives, on the screen the user waits
longest on, and it reads as a rendering fault rather than as a load finishing.
The inner `SkeletonLoader` blocks keep `surfaceWarm2` with **no** edge and **no**
shadow: they are fills, not surfaces, and an edged block inside an edged card
would be noise. Their corner default moved from a bare `8` to `SiftRadii.rInline`
so the text-line blocks match the card they stand in for.

**Row separators — the deliberate non-change, with the arithmetic.** All eight
`Divider(...)` call sites pass an explicit `thickness: 1` and **keep it**. The
themed `dividerTheme.thickness` **was** raised to `SiftBrutal.borderW` so that a
`Divider` which does not override it is a deliberate rule.

The argument against propagating it, in one line: what makes these rules quiet is
their **colour**, not their weight. `divider` measures **1.42:1** on `paper` and
**1.37:1** on `canvas` in light — a whisper. A 2pt rule in that colour is the
same whisper drawn twice as thick, which reads as *heavier*, not as *more
visible*. And every one of the eight is an **intra-surface row separator**:
Settings checklist rows, Detail's File/Scanned/Type table, shopping items,
action-history rows, the About feature rows, the Onboarding trust rows. A 2pt
line between two rows of one table marks a boundary that is not there, while the
2pt edges around every actual container get quieter by comparison.

The alternative the brief raises — "short rules or gaps instead" — was considered
and rejected: removing them is a layout change (§9), and a short rule would need
a width that is a design decision with no user benefit over a full-width hairline
at this contrast.

`test/brutal_surface_test.dart` pins the count (8) so "we raised the theme and
forgot the call sites" cannot be mistaken for "we decided this".

### 4.16 The OCR block

| | Fill | Border | Corner | Shadow | Copy control |
|---|---|---|---|---|---|
| OCR block | `codeBg` (unchanged) | `surfaceEdge` @ B | `rControl` | `hard(isDark)` | `BrutalButton.outline`, height 36 |

**Before → after:** `rThumb 12`, no border, no shadow → `rControl` 4 + 2pt
`surfaceEdge` + `hard`. This was the ONE surface the spec explicitly excluded,
on the reasoning that "a hard border plus a cast shadow on a copy affordance
would make the text look broken". Both mechanical concerns behind that were
checked and neither survives:

- **The text does not move and does not change.** The block is still
  `SelectableText` in `SiftType.ocrMono` at 13pt/1.6, `codeText` on `codeBg`, at
  the same 16/16 padding. Its contrast is unchanged because its **fill** is
  unchanged: **13.06:1** light, **14.20:1** dark.
- **The truncation is untouched.** The 500-character cap is
  `ChatEngine._ocrCharsPerScreenshot` in `chat_engine.dart`, not the detail
  screen; neither file was edited in that respect, and the test file asserts
  both halves so a future edit cannot quietly add a second truncation.
- **The edge is the tightest row in the whole system and still clears 3:1:**
  `stone` on `codeBg` is **3.45:1** light and **5.74:1** dark. `codeBg` is a
  near-black slab in *both* modes, so it is neither a page step nor one of the
  four slab fills; `surfaceEdge` was extended to cover it rather than a
  per-surface colour being invented. (`bone` would also have cleared it, at
  7.57:1 in light, but from a different palette step than every other surface's
  edge — which is the one thing the token exists to prevent.)

**The copy button is now `BrutalButton.outline`, and the variant is forced:**

- Not the **ghost**: a ghost has no fill to lift it, so its default `ink` label
  would measure **1.14:1** on this `codeBg` fill. A ghost cannot be used on a
  near-black slab at all.
- Not `filled`: an `accentDeep` slab floating in a dark block would be a second,
  unrelated accent mass in the middle of a read-only surface.
- `outline` gives `paper` on `codeBg` — 16.27:1, and the button becomes the
  brightest thing in the block, which is correct: it is the only thing in there
  you can touch.

Height stays **36** and horizontal padding stays `SiftSpacing.s12`, matching the
`minimumSize: Size(0, 36)` and `EdgeInsets.symmetric(horizontal: 12, vertical: 6)`
the Material button had, so the block does not grow. The label keeps
`SiftType.metaLabel` rather than `buttonLabel` — it is meta copy and §9 forbids
a typography change. 12pt is the *restored* size, not a new one: the Material
`TextButton` styled its child with `metaLabel`, so the reversal must match it
(`microLabel` here would have been a silent 1pt reduction). At 12pt/1.3 the text
is 15.6dp, still under the 16dp icon, so `height: 36` does not grow. The label
also sets **no colour of its own**, which is what lets
`DefaultTextStyle.merge` supply the per-state label. A `codeText` label would
have been 1.00:1 on the outline variant's `paper` fill.

The migration is a net accessibility gain, not just a style change: the Material
`TextButton` gave the control a `TextButton`-level focus side and no explicit
`Actions`, and `BrutalButton` brings `brutalActivate`, a 2pt ring that clears
3:1 against its own fill, and `Semantics(button: true)`. **The app now contains
zero Material buttons.**

---

## 5. The press behaviour as a Flutter problem

### 5.1 The constraint, stated honestly

**VERIFIED against the live Flutter API** (`api.flutter.dev/flutter/material/ButtonStyle-class.html`, fetched during authoring). The `ButtonStyle` constructor's complete property list is:

`textStyle, backgroundColor, foregroundColor, overlayColor, shadowColor, surfaceTintColor, elevation, padding, minimumSize, fixedSize, maximumSize, iconColor, iconSize, iconAlignment, side, shape, mouseCursor, visualDensity, tapTargetSize, animationDuration, enableFeedback, alignment, splashFactory, backgroundBuilder, foregroundBuilder`

Therefore:

1. **There is no `boxShadow` property.** Confirmed. `shadowColor` is `WidgetStateProperty<Color?>` and is consumed by the `Material`'s elevation shadow only — it cannot supply an offset or a blur radius.
2. **`elevation` cannot produce a hard shadow.** Material elevation shadows are Gaussian-blurred ambient shadows drawn by `PhysicalShape`. With `blurRadius: 0` semantics unavailable through the button path, an `ElevatedButton` at elevation N always blurs. The app already sets `elevation: WidgetStatePropertyAll(0)` everywhere (`app_theme.dart:686`, `:713`) precisely because Material elevation fights the flat-paper thesis.
3. **`shape` is `OutlinedBorder`**, which carries a `BorderSide` and a `BorderRadius` and nothing else. It can deliver the 2pt border and the 4pt radius. It cannot deliver a shadow.
4. **There is no transform hook.** A `ButtonStyle` cannot translate its own child.

Two escape hatches exist and are **rejected**, with reasons:

- `backgroundBuilder` / `foregroundBuilder` (`ButtonLayerBuilder`) could wrap a `Container` carrying a `boxShadow`. Rejected: the builder's output is a child *of* the `Material`, so the shadow is clipped to the Material's own shape, it is version-sensitive, and it produces a control whose press behaviour lives in a widget that is neither the button's `State` nor its `InkWell` — which makes the §5.2 press contract and the §4 focus-state swap awkward to reason about.
- Painting the hard shadow in the **parent** of each button. Rejected for the same reason plus one more: 29 call sites means 29 chances to get the gutter wrong, and a shadow that is a sibling of the control rather than a property of it will drift.

**Conclusion: Material button widgets cannot express this design. A custom widget is required, not merely preferred.**

### 5.2 `BrutalButton`

New file: `lib/widgets/brutal_button.dart`.

```dart
enum BrutalVariant { filled, outline, text, destructive }

class BrutalButton extends StatefulWidget {
  final BrutalVariant variant;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;          // null → no icon; the layout is identical
  final double height;         // default SiftSpacing.btnH (48); text → 40
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel; // null → child text is the label
  final bool expand;           // true → SizedBox(width: double.infinity)

  const BrutalButton({super.key, required this.onPressed, required this.child, this.variant = BrutalVariant.filled, this.icon, this.height = SiftSpacing.btnH, this.padding, this.semanticLabel, this.expand = false});

  BrutalButton.icon({super.key, required this.onPressed, required this.icon, required this.label, this.variant = BrutalVariant.filled, this.height = SiftSpacing.btnH, this.padding, this.semanticLabel, this.expand = false});

  const BrutalButton.text({super.key, required this.onPressed, required this.label, this.icon, this.height = 40, this.padding, this.semanticLabel, this.expand = false});

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}
```

Build contract for `_BrutalButtonState`:

```
Semantics(
  button: true,
  enabled: widget.onPressed != null,
  label: widget.semanticLabel,
  child: brutalActivate(                                // Enter/Space; see §5.3
    onActivate: widget.onPressed,
    child: Focus(                                       // own Focus, not the theme's
    onFocusChange: _setFocused,
    child: MouseRegion(
      onHover: _setHovered,                           // tracked but intentionally unused; see §4.0
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(                          // owns press state
        onTapDown:  widget.onPressed == null ? null : (_) => _setPressed(true),
        onTapUp:    widget.onPressed == null ? null : (_) => _setPressed(false),
        onTapCancel:widget.onPressed == null ? null : () => _setPressed(false),
        child: AnimatedContainer(                      // duration: MotionTokens.press
          duration: _pressed ? SiftBrutal.pressIn  : SiftBrutal.pressOut,
          curve:    MotionTokens.easeOutCubic,
          height:   widget.height,
          width:    widget.expand ? double.infinity : null,
          padding:  widget.padding ?? const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:      _fill(context),
            borderRadius: ghost ? null : BorderRadius.circular(SiftRadii.rControl),
            border: _border(s, isDark),   // null only on an unfocused ghost; stone or focus on a
                                         // page step, edgeOnFill or focusOnFill on a slab (§6.10)
            boxShadow: _shadow(context),
          ),
          child: Row(                                 // mainAxisSize.min unless expand
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [ if (icon != null) ...[IconTheme.merge(color: labelColor, child: icon!),
                                                const SizedBox(width: 8)],
                         Flexible(child: DefaultTextStyle.merge(style: _labelStyle(context),
                                                                child: widget.child)) ],
          ),
        ),
      ),
    ),
      ),
    ),
  ),
)
```

`AnimatedContainer` cannot paint a `Transform`. So the translate is a **separate outer `Transform.translate`** wrapping the `AnimatedContainer`:

```
Transform.translate(
  offset: _pressed && MotionTokens.enabled ? SiftBrutal.offset : Offset.zero,
  child: <AnimatedContainer above>,
)
```

This is a paint-time matrix, not a layout change, and `transformHitTests` defaults to `true` so the translated box hit-tests in its shifted position — which is correct and does not affect the in-flight tap (see §5.3).

Reduced motion: `MotionTokens.enabled` is false → `offset` stays `Offset.zero` and `AnimatedContainer`'s duration is `Duration.zero` (because `SiftBrutal.pressIn/pressOut` delegate to `MotionTokens.press/pressRelease`, which are already `Duration.zero` when reduced). The fill inversion still fires. The shadow still collapses. Nothing moves.

`_shadow(context)` returns, in order of precedence: `SiftBrutal.none` when disabled; `SiftBrutal.hardPressed(isDark)` when `_pressed`; `SiftBrutal.hard(isDark)` otherwise; `SiftBrutal.none` for `BrutalVariant.text` at rest.

### 5.3 Accessibility contract for a custom button

A hand-rolled `Material` + `InkWell` button is where custom widgets usually regress. All six requirements are mandatory and each is checkable:

1. **Semantic role.** Wrap in `Semantics(button: true)`. A bare `InkWell` does **not** set the button flag — it only contributes `onTap`. Without the explicit `Semantics(button: true)`, TalkBack announces "double tap to activate" on a plain object instead of a button, and the rotor loses the Buttons list.
2. **Accessible name.** `Semantics(label: widget.semanticLabel)` when provided; otherwise the `Text` descendant supplies the name. Every one of the 29 call sites already passes a `Text` or `label:`, so all 29 get a name for free. `semanticLabel` exists for the icon-only shapes (e.g. the tag add-circle) and must be set there.
3. **Enable/disable.** `enabled: widget.onPressed != null` plus `onTapDown`/`onTapUp`/`onTapCancel` all null when disabled, plus `SystemMouseCursors.basic`. Disabled buttons must announce as disabled — that is what `enabled:` drives.
4. **No ink splash.** The app sets `splashFactory: NoSplash.splashFactory` globally (`app_theme.dart:587`). A hard-edged control with a circular ink splash would reintroduce the softness this design removes. Do not add a `Material`/`InkWell` for ink; the `GestureDetector` above is sufficient because there is no ink to draw.
5. **48dp minimum touch target.** `height` defaults to `SiftSpacing.btnH` = 48, including the 2pt border, for every non-ghost variant. Ghost uses 40 to match the existing `textButtonTheme` minimum. `expand: true` is required at the three call sites that currently wrap the button in `SizedBox(width: double.infinity)` — `about_dialog.dart:74-75`, `onboarding_screen.dart:105-106`, `detail_screen.dart:871-872` — so those rows keep their current width.
6. **A 4dp translate cannot cause a missed tap.** Hit-testing resolves on pointer **down**, before `_pressed` becomes true and before the transform applies. The gesture recogniser already owns the arena, so the subsequent pointer-up completes the tap regardless of where the widget has moved. A second simultaneous pointer could hit-test differently against the 4dp-shifted box; accepted, and imperceptible at 4dp.

**A seventh thing, added during implementation, and it is not optional.** Dropping `Material`/`InkWell` drops something `InkResponse.build` supplied for free: an `Actions` ancestor binding `ActivateIntent` and `ButtonActivateIntent`. Without it the control is reachable and announced but **inert** — a keyboard user tabs to it, sees the ring light, presses Enter or Space, and nothing happens, which is an SC 2.1.1 and SC 2.4.7 failure that a screenshot and a colour assertion both miss. Every brutal control therefore wraps its `Focus` in `brutalActivate` (`brutal_activate.dart`), which registers both intents against the control's own `onPressed` and registers them even when disabled, so Enter cannot activate something the pointer cannot press. It has to wrap the `Focus` rather than sit inside it: the key event dispatches from the focused node's own context upwards, so an `Actions` below the focus node is unreachable. `BrutalButton`, `SiftBrutalChip` and the bottom sheet's `_SourceOption` all carry it.

### 5.4 Focus ring — in-place perimeter, and why

**The ring is a 2pt border drawn in the control's own box, replacing that box's resting edge.** It is not a second ring and it is not offset outside the control's bounds. Which colour fills it depends on what the box is filled with — `F` on a page step, `F'` on a slab (§4 conventions, §6.10). An earlier version of this section specified `F` unconditionally on the reasoning that the ring "replaces the border so it never sits on the fill". That reasoning was wrong: a `BoxDecoration` border paints inside the box, on top of `decoration.color`, so the ring is always on the fill, and on the light filled button `F` **is** the fill.

This was a judgement call, and the alternative was specified and rejected:

- *Outward-offset ring (as originally framed).* Requires either reserving a 2pt layout gutter on every side — which changes the footprint of all 29 call sites and brushes against the no-layout-change non-goal (§9) — or shrinking the fill box from 48 to 44 while focused, which introduces a scale change that is neither the press translation nor a colour change, and reads as a bug.
- *In-place perimeter ring (chosen).* Zero layout change, zero clipping risk, 2pt of solid focus colour around the full perimeter, and it is already the mechanism the app uses at `app_theme.dart:688-690` and `:715-718` — a border that appears on focus, in the same 2pt slot the resting edge already occupies. What changes versus today is that the ring goes from a 1.5pt `accent` side (which does not clear 3:1) to a 2pt side that does clear 3:1 **against the fill it is painted on**, and that it is a `BoxDecoration` border resolved from `SiftBrutal` rather than a Material `BorderSide` resolved from the theme.

Choosing the in-place ring is what makes the page-step/slab split unavoidable rather than optional. An outward ring would sit outside the box, clear of the fill, and one focus colour would then serve every surface. In-place is the better contract for a hard-edge language — it is the only one that needs no layout gutter on 29 call sites — and it costs a second focus pair. That trade is stated, not hidden.

A reviewer who prefers the outward ring should treat it as a change to this section, not to §4 — the per-surface state tables are unaffected.

### 5.5 Migrating the 29 call sites

Mechanical, name-for-name, no logic touched:

| Existing | Replace with | Notes |
|---|---|---|
| `FilledButton(onPressed:, child:)` | `BrutalButton(onPressed:, child:)` | |
| `FilledButton.icon(onPressed:, icon:, label:)` | `BrutalButton.icon(onPressed:, icon:, label:)` | |
| `OutlinedButton.icon(onPressed:, icon:, label:)` | `BrutalButton.outline.icon(onPressed:, icon:, label:)` | 2 sites: `chat_atoms.dart:458`, `detail_screen.dart:873` |
| `TextButton(onPressed:, child:)` | `BrutalButton.text(onPressed:, label:)` | label is the `Text` |
| `TextButton.icon(onPressed:, icon:, label:)` | `BrutalButton.text.icon(onPressed:, icon:, label:)` | `chat_atoms.dart:468` only |
| `FilledButton` + `SizedBox(width: double.infinity)` | `BrutalButton(expand: true, ...)` | drop the `SizedBox` — 3 sites |
| `settings_screen.dart:1030` | `BrutalButton(variant: BrutalVariant.destructive, ...)` | the only destructive adoption |

Preserve at each site: the `onPressed` body verbatim, the `Text`/`label` string verbatim, and any `if (MotionTokens.canHaptic) …` already inside the callback. Do not add haptics that were not there — the press now carries its own feedback, and DESIGNSTATE's haptic budget is deliberately sparse.

Two `FilledButton.icon` sites carry a `CircularProgressIndicator` as their icon while a long action runs — `detail_screen.dart:526-535` and `:876-881`. `BrutalButton` must accept an arbitrary icon widget, and the pressed fill inversion must **not** run while that indicator is showing (the control is busy, not pressed). The `onPressed: _running ? () {} : _runAction` pattern already prevents a press; keep it.

~~Do **not** migrate `detail_screen.dart:324` (OCR copy). See §2.5.~~ **Superseded by the §2.5 reversal.** The OCR copy button is migrated as the 30th `BrutalButton`, as an `outline` variant; §4.16 gives the three-part argument for why `outline` rather than `text` or `filled`, and why the height and label typography were pinned to what they were.

After migration, the three button theme blocks at `app_theme.dart:657-736` become dead for the app's own widgets. Leave them in place: they are the fallback for any Material button a dependency or a future screen introduces, and deleting them would be an unrequested change. Add a one-line comment to each saying so.

---

## 6. Risks and fixes

Likelihood: **H** high · **M** medium · **L** low.

### 6.1 Incoherence — hard controls on soft cards read as a rendering fault

- **What goes wrong.** A 2pt hard-edged terracotta button sitting inside a soft, 20pt-radius, hairline-bordered paper card looks like two design systems in one screen. Users read it as a rendering error, not a choice, and the app feels unfinished.
- **How it shows up.** The Detail action bar was the worst case: a brutal `BrutalButton` directly under a 20pt-radius `paper` stack. Settings, with three brutal buttons inside flat borderless rows, was the second worst.
- **Likelihood.** **H** — and **it happened.** This was not a hypothetical that the §2.5 exclusion list successfully prevented; it is what the user saw on the device and rejected.
- **Fix, as originally specified.** (a) The §1 grammar, so the pairing is a *system* (paper = read, hard = operate) rather than a collision. (b) Restraint: 29 buttons out of a large surface area.
- **Why (a) and (b) failed.** The grammar needed a *rare* signal to be learnable, and the hard edges did not land in a rare distribution — they clustered in action rows, empty states and dialog footers, which is not something a reader learns once. Restraint also has a cost that was not counted: the surfaces the rule implicitly blessed carried `divider` hairlines at **1.42:1** light and **1.22:1** dark, and a screenshot of that looks *fine*. The rule was licensing an invisible defect and calling the result coherent.
- **The fix that shipped.** Reverse the rule and put one language on every surface (§1, §4.9–§4.16). The containment strategies the old fix relied on were: **card**, **dialog**, **bottom sheet**, **snackbar**, **banners**, **skeletons**, **the user bubble**, **the OCR block**, **badges/tags**, and the three floating bars. Six rows inside a hard container stay soft (§2.5), which is what keeps a Settings list from becoming a wall.
- **What this risk now looks like.** Inverted. The failure mode is *half* — a card updated and the sheet beside it not, or the three banners updated and the error banner not. That is why every one of the sixteen surfaces builds through `brutalEdge(...)` and why `brutal_surface_test.dart` walks them.

### 6.2 Overuse — the distinction collapses

- **What goes wrong.** If every surface is hard, "hard" stops meaning "operable" — but under the new §1 that is no longer the failure, because "hard" no longer claims to mean operable. What would collapse instead is **depth**: surfaces, controls and labels must stay tellable apart.
- **How it shows up.** If a label grows a cast shadow, it reads as pressable and the user taps a `TypeBadge`. If a `BrutalButton.text` gains one, a "Skip" button acquires primary visual weight.
- **Likelihood.** **L**, and it is now structural rather than budgetary: §4.9's table is the rule (surface casts, label does not, control casts *and* sinks), and the test asserts that a label and a chip differ **only** in shadow.
- **Fix.** The distinction is carried by **three channels, none of them hue**: (1) shadow — surface casts, label does not, control casts and collapses it on press; (2) state — a control translates, rings and inverts its fill, a surface never does; (3) alignment and typography — the chat bubble is right-aligned and sans, the assistant essay is left-aligned and serif. §6.2's escape hatch (make the ghost an outline) was **not** taken.

### 6.3 Inconsistent shadow direction

- **What goes wrong.** One button's shadow at `(4, 4)`, a chip's at `(3, 3)`, a sheet option's at `(4, 2)`. Two different light directions in one app reads as a bug far more strongly than either direction alone.
- **How it shows up.** As a single off-spec surface. It is the most visible possible single-surface error, because the eye is trained by the others — and after the reversal it is trained by *sixteen* of them.
- **Likelihood.** **L** if the token is used as specified; **H** if anyone writes a `BoxShadow` literal.
- **Fix, and it is now enforced mechanically rather than by review.** One constant, `SiftBrutal.offset`, with no per-component override. `brutalEdge(...)` (§3.1) is the single constructor for every read-only surface's decoration, so a per-surface shadow is a function argument rather than a literal. **`test/brutal_surface_test.dart` asserts that no `BoxShadow(` literal exists in `lib/` outside `app_theme.dart` and `brutal_tokens.dart`,** and a second test asserts that no visible surface still resolves a `SiftElevation` step. The old instruction — "add that grep to the Phase 5 coherence review" — is now a test that fails the build.

### 6.4 Dark-mode invisibility

- **What goes wrong.** A black hard shadow on `canvas #1F1B16` is invisible: contrast = 0.06133/0.05 = **1.23:1**. A shadow that does not render is not a subtle shadow, it is a border that is 4px too thick and an unexplained 4px gap of dead space under every control.
- **How it shows up.** In dark mode only, so it survives a light-mode review entirely. Users see buttons that appear to float with a gap.
- **Likelihood.** **H** without the fix — this is the default outcome if anyone reaches for a black shadow.
- **Fix.** Specified and derived in §3.1: in dark mode the offset edge **inverts to a light value**, `Color(0x73E8E0D2)`, chosen so it clears 3:1 against `canvas` (3.69:1), `paper` (3.54:1), *and* the dark filled button's own cream fill (3.54:1). The one surface it does not clear 3:1 against is a saturated `error` fill (1.65:1) — and that is irrelevant, because the offset means the shadow is only ever visible on its sliver, which sits on the page. Verify in both modes at Phase 1, not at Phase 5.

### 6.5 Touch-target regression

- **What goes wrong.** A 2pt border is drawn *inside* the widget's bounds, so naively "keeping the visual size the same" would shrink the tappable box, or adding the border outside the bounds would grow the layout. Either error costs real users with motor impairments.
- **How it shows up.** `BrutalButton` at height 48 has a 44dp interior; if a future edit adds the border outside, the row grows 4dp and `about_dialog.dart:74-75` and `onboarding_screen.dart:105-106` (both `double.infinity` full-width) shift.
- **Likelihood.** **L** — but the failure is invisible in a screenshot and only shows up in a TalkBack swipe-through.
- **Fix.** Total height including the border stays `SiftSpacing.btnH` (48); the border is painted inside, giving a 44dp interior — above Material's 40dp floor and with the full 48dp available to the pointer. **No `SiftSpacing` value changes.** The 4dp press translate cannot cause a missed tap because hit-testing resolves on pointer-down (§5.3.6). Test explicitly: TalkBack / keyboard focus traversal must reach every one of the 30 buttons in document order.

### 6.6 Reduced motion

- **What goes wrong.** A press effect that is carried *only* by the transform communicates nothing when the transform is disabled. The user presses a button and the only evidence is the tap sound.
- **How it shows up.** Only for users with `MediaQuery.disableAnimationsOf` true, which routes through `main.dart:146` → `MotionTokens.reduced`. Never seen in a normal review.
- **Likelihood.** **H** if the fill inversion in §4.1 is dropped as redundant.
- **Fix.** The press carries **three** independent signals: (1) the 4dp translate, (2) the hard shadow collapsing from a 3.64:1 sliver to nothing, (3) the **full fill inversion to `ink`/`canvas`**. Under reduced motion, (1) and (2) become instantaneous and (3) is a 0ms colour swap — so the press is *more* reliable under reduced motion, not less. This is a free consequence of delegating `SiftBrutal.pressIn/pressOut` to `MotionTokens.press/pressRelease` rather than declaring new durations. Do not add a hardcoded `Duration` anywhere in `brutal_button.dart`.

### 6.7 Performance on low-end devices (target includes 2GB Android phones)

- **What goes wrong.** The general worry is that drop shadows force offscreen buffers and repaints. This design does not have that problem, and the reason is worth stating because it is counter-intuitive.
- **How it shows up.** It would show up as jank on the Settings screen, which is the densest cluster of brutal controls (7 buttons + 3 switches + 5 inputs).
- **Likelihood.** **L.**
- **Fix / assessment — this risk is low, and here is why.** A `BoxShadow` with `blurRadius: 0` and no `spreadRadius` is an offset copy of the same rounded-rect path. Skia draws it as a straight offset fill: **no Gaussian convolution, no offscreen layer, no `saveLayer`, no shader.** A 2pt border is four strokes already present in the RRect path. The press is a `Transform.translate`, which is a paint-time 2×3 matrix with no relayout and no repaint invalidation of the shadow.
  **The decisive comparison: the app already ships ambient shadows that are strictly more expensive.** `SiftElevation.l3` is `blurRadius: 16` (`app_theme.dart:68-70`) on every library card, and `l4` is `blurRadius: 24` (`:71-73`) on every dialog and sheet. A `blurRadius: 24` Gaussian *does* allocate and blur. The hard shadow is cheaper than what is already rendering on every card in the app. The change is a net reduction in rasterisation cost for any screen where a brutal control replaces a card.
  Confirm during implementation: `brutal_tokens.dart` and `brutal_button.dart` must contain **no** `BackdropFilter`, no `ImageFilter`, no `Shader`, no `ClipPath`, and no `RepaintBoundary`. The last one matters — adding a `RepaintBoundary` per button would promote 30 layers and *would* be a real regression on a 2GB device.
  Only open question: `Transform.translate` on a widget with an `AnimatedContainer` child may cause the engine to treat the subtree as a composited layer. At 4dp with a handful of buttons on screen this is negligible, and it is the same mechanism the existing `SiftSendCircle` / `_CameraCircle` press-scale already uses (`chat_screen.dart:733`, `home_screen.dart:964`). Not worth a `RepaintBoundary`.

### 6.8 Print / thumbnail scaling

- **What goes wrong.** A 2pt border dominating a surface that renders small.
- **How it shows up.** At chip size, or in any future image-export path.
- **Likelihood.** **L**, and the risk is currently nil.
- **Assessment — no target surface renders below 20dp, and there is no print path.** The smallest brutalized surface is now `TypeBadge`, at ~20–28dp depending on `compact`, where a 2pt border is 7–10% of the height. That is heavier than the 32dp chip's 6.25%, and it is the one place this risk is not "visible but not dominant": at 20dp with `microLabel` at 11pt, the border is the same visual order as the type. It was accepted because a badge is a *label*, it has no shadow to amplify the edge, and the interior still clears the 11pt/1.3 line box (20.3dp interior against a 14.3dp line at `compact`). **If a device review disagrees, the fix is a thinner badge edge, not a smaller radius** — and a badge is a label, so it would be the one surface allowed a 1pt edge. Nothing else goes below 36dp: the OCR copy button is 36dp and is now inside the brutal set, and the chat send circle and the other circular controls remain excluded.
  The app has **no print pipeline and no image export** — DESIGNSTATE.md:122 records the Share affordances as removed for lack of a dependency, and there is no rendering-to-bitmap path for any brutal surface. The 96px `cacheWidth` thumbnails (`chat_atoms.dart:241`) are read-only evidence and are excluded (§2.5). So the only place this risk could materialise is a future screenshot-to-image feature, at which point it is a new problem. Re-check it if such a feature lands.

### 6.9 Test breakage

- **What goes wrong.** A source-scanning test breaks because a migration reordered or reworded code it asserts on positionally.
- **How it shows up.** `flutter test` red on files that have nothing to do with visuals.
- **Likelihood.** **L**, with one file worth naming explicitly.
- **Fix / assessment.** Enumerated from the working tree:

  | Test file | Reads source? | Risk |
  |---|---|---|
  | `test/widget_test.dart` | no | **None.** Placeholder (`1+1==2`); cannot break. |
  | `test/screenshot_analyzer_test.dart` | yes — `home_screen.dart`, `settings_screen.dart`, `onboarding_screen.dart`, `chat_screen.dart`, `privacy_gate.dart`, `about_dialog.dart`, `actions_history_screen.dart` | **None.** All assertions are on *string literals* ('Local-only mode', 'images and OCR text stay on this device', 'image-labeling model on first use', 'screenshot-derived text and context', 'source lookup'). Swapping `FilledButton` → `BrutalButton` does not touch a single one, and neither does the §2.5 reversal. Also asserts `settings` contains `bool _localOnly = true;` — untouched. |
  | `test/delete_everything_test.dart` | yes — `settings_screen.dart`, `chat_screen.dart`, `main.dart` | **Low, and it is a live hazard unrelated to this work.** `:391` asserts `source.substring(callIndex, callIndex + 40)` contains `'catch'` immediately after `await provider.deleteEverything();` — a **positional** assertion with a hard-coded window length. It passes on an LF checkout and **fails on a CRLF checkout** (Windows), because 40 characters after the call is then `\r\n    ` and nothing else. It also asserts `isNot(contains('Nothing was deleted'))` and two `indexOf` orderings. None of the files it reads was touched by the §2.5 reversal. |
  | `test/local_model_arch_gate_test.dart` | yes — `settings_screen.dart` | **None.** Asserts `service.unsupportedDeviceNote` present and `indexOf('service.startDownload()') > indexOf('if (!service.isSupportedDevice) {')`. Untouched by visuals. |
  | All other test files | no | **None.** No test asserts on a widget type, a radius, a colour, or a shadow — with the single exception the reversal forced: `test/brutal_dialog_test.dart`, below. |

  **The one existing test the §2.5 reversal had to change, and why.** `brutal_dialog_test.dart` contained a test named *"the dialog chrome itself stays warm"*, which asserted `rCard 20` and `BorderSide.none` — the §2.5 exclusion, written down and pinned. It was **inverted**, not deleted: it now asserts `rControl`, a non-`none` side at `SiftBrutal.borderW` in `SiftBrutal.surfaceEdgeLight`, `elevation: 0`, and that the edge clears 3:1 against the `paper` fill — and a dark-mode case was added beside it. Its sibling assertion, that the *action row* carries the hard edge, was left untouched and still runs against the real `privacy_gate.dart` dialog. **A test that pins a decision must be changed when the decision is reversed; that this one existed is a point in favour of having written it.**

  **New source-scanning tests added by this phase** are in `test/brutal_surface_test.dart`: the OCR copy button is migrated, `SelectableText` + `SiftType.ocrMono` survive, `ChatEngine._ocrCharsPerScreenshot == 500` is untouched, and no `BoxShadow(` literal exists outside the two token files. No runtime string literal was added or changed anywhere.

### 6.10 Focus ring invisible on the accent — the named risk

- **What goes wrong.** A terracotta `accentDeep` filled button with a terracotta focus ring. Ring on fill = 1.00:1. The focus indicator is completely invisible, which is a WCAG 2.1 SC 2.4.7 failure on the most important control in the app.
- **How it shows up.** Keyboard and switch-access users tabbing to a primary action and getting no feedback at all.
- **Likelihood.** **H**, and it is not hypothetical: this shipped, in every mode, on every slab.

**The premise this section used to rest on was false, and it was found during implementation.** The old fix was "`F`-on-`stone`, and the ring never sits on the fill, so the requirement is against the page and `F` clears it with margin — therefore one focus colour solves both modes." Each clause fails on inspection:

- A `BoxDecoration` border paints **inside** the box and **on top of** `decoration.color`. The border is the fill's own outermost 2pt, so a ring drawn there is always on the fill. "Replaces the border" is not the same as "sits outside the fill."
- Scored against the page, the same `F` looked fine — 4.79:1 on `canvas`, 4.99:1 on `paper` in light. Scored against the fill it is arithmetically blind:

  | Slab | Ring | Fill | Ratio | |
  |---|---|---|---|---|
  | filled, light | `focusLight` `accentDeep` | `accentDeep` | 0.19996 / 0.19996 | **1.00:1** |
  | destructive, light | `focusLight` `accentDeep` | `error` | 0.19996 / 0.18241 | **1.10:1** |
  | filled, dark | `focusDark` `accent` | `ink` | 0.33636 / 0.80123 | **2.38:1** |
  | selected chip, light | `focusLight` `accentDeep` | `ink` | 0.19996 / 0.06987 | **2.86:1** |
  | switch on, light | `focusLight` `accentDeep` | `accentDeep` | 0.19996 / 0.19996 | **1.00:1** |

  Every row is below SC 1.4.11's 3:1. The two at 1.00:1 are a total absence of an indicator; the other three are a weak one.
- The same false premise left the **resting** edge of the light filled button at `stone` on `accentDeep` = **1.06:1** — a 2pt border, the one the whole hard-edge language rests on, that drew nothing. That was not a focus defect at all, and it was invisible for the same reason.

**The rule that replaced it: a control's box is either a PAGE STEP or a SLAB.**

| | Page step | Slab |
|---|---|---|
| The box is filled with | `paper`, `surfaceWarm1`, `surfaceWarm2`, or nothing | `accentDeep`, `error`, `ink` |
| Resting edge | `stone` | `E` = `edgeOnFillLight` / `edgeOnFillDark` |
| Focus ring | `F` = `focusLight` / `focusDark` | `F'` = `focusOnFillLight` / `focusOnFillDark` |
| Surfaces | outlined button, ghost, field, chip at rest, bottom-sheet option, `TagChip` delete target, OCR copy button, and **every disabled control** (`surfaceWarm2` is a page step even on the `filled` variant) | filled button, destructive button, selected chip, switch ON track |

A slab ring cannot be a darker shade of the slab — the fill is the shade. It is the value the slab is **never** filled with, which is the control's own **foreground**: the colour every slab is already painting its label or thumb in. That costs no new hue in either mode, and one value per mode covers every slab fill, because the palette offers nothing else. The only light steps clear of `accentDeep` are `paper` / `onAccent` / `canvas` (4.79–4.99:1) and the only dark one clear of `ink` is `canvas`; `bone` is 2.32:1 and `ink` itself 1.00:1. Measured against its own fill, the new pair gives 4.99 / 5.47 / 14.28 in light and 13.06 / 6.10 / 3.26 in dark — the full table with its arithmetic is §7.1.

`F'` follows the press, which inverts the fill exactly as it inverts the label (§4.1): the dark press fill **is** `canvas`, i.e. the dark ring, so a dark button held down while focused would show 1.00:1. Hence `focusOnFillPressedDark` = `ink`. The light pair needs no flip — `onAccent` is 14.28:1 on the light press fill (`ink`).

**The trade-off this makes, stated so a reviewer can overrule it.** `E` is `bone`, and `bone` is deliberately a **modest** step from the ring — 2.15:1 in light (0.99793 / 0.46409) and 2.15:1 in dark (0.13182 / 0.06133) — so focus reads as *the same edge getting brighter* rather than as an inversion. The more dramatic alternative was an `ink` resting edge, 14.28:1 from the ring, which would have made focus unmistakable. It was rejected because `ink` **is** the selected chip's own fill, in both modes: an `ink` edge on a selected chip is 1.00:1, and the control whose resting border had become invisible was exactly the one whose focus ring had. One shared `E` is worth more than a bigger jump on a subset. `bone` also maximises the worst case across the alternative steps (`stone` 1.06, `graphite` 1.38, `ink` 1.00, `error` 1.00), and SC 1.4.11's 3:1 is not owed by a resting edge in any case — what it owes is being visible, and 2.32:1 where the defect was 1.06:1 is.

**Known limitation, not hidden: the focused light filled button's ring is 1.04:1 against the cream page.** `onAccent` on `canvas` is 0.99793 / 0.95775 = **1.04:1**, so the outer edge of the ring merges with the page it sits on and only the ring-vs-fill contrast is doing any work. This is not fixable with the palette: every light step that clears 3:1 against the `accentDeep` fill is itself page-coloured (`paper` 4.79, `onAccent` 4.99, `canvas` 4.79) and would vanish against `canvas` instead. SC 1.4.11's 3:1 is scored against the **adjacent fill** — the side the ring physically sits on — so the ring is conformant, and the fill-side reading is the correct one. But a reader should know the outer edge merges, because a screenshot of a focused light button on a cream page will look like a soft halo rather than a hard 2pt line, and that is the expected rendering.

Do not draw the ring as a Material `focusColor` overlay (`app_theme.dart:590` sets `focusColor: accent @ 0.18`, a translucent wash that is a glow, not an edge). `BrutalButton` must set `focusColor: Colors.transparent` locally so no Material wash bleeds under the hard ring.

### 6.11 Risks I would weight higher than they were in the brief

Three, in order:

1. **The ghost-button hole (§4.3).** Twelve of the 29 call sites are ghost text buttons and they get *no* mark. That is a fifth of the brutalization budget spent on the one class that does not carry the grammar, and it is the most likely source of "this doesn't feel like neobrutalism yet." I have judged restraint to be correct here, but this is the decision most likely to be wrong, and it is one line to change.
2. **The chip radius change (§4.6).** Moving three chip classes from `BorderRadius.circular(999)` to `rControl` changes a shape the eye has already learned, in three files, at once. It is the largest single visual delta in the whole spec after the buttons, and the least obviously an improvement. It is isolated in Phase 3 for that reason. If Phase 3 review dislikes it, the fix is to keep the pill and drop the hard shadow on chips — but that breaks §6.3's single-token rule, so it would need a spec amendment, not a local patch.
3. **Dark-mode switch thumb (§4.7).** Changing the dark unselected thumb from `paper` to `stone` and the dark selected thumb from `paper` to `canvas` is a *behaviour* fix, not a style change: today the thumb is at 1.22:1 against its own track and is effectively invisible. Bundling it into a "brutalism" change will make it look like scope creep, and a reviewer may try to revert it. Do not revert it. It is in this spec because the 2pt track outline is what makes the thumb's position legible, and the thumb had to be fixed before the outline could be judged.

### 6.12 What the §2.5 reversal did to these three risks

- **The ghost-button hole (§6.11.1) is now much wider, and it still exists.** Twelve ghost buttons still carry no mark — but they now sit inside hard-edged dialogs, sheets and bars, so their *container* says "operate this" while their *type* says nothing. That is a real hole and it got worse. It did not get fixed because the honest fix is the one §6.2 rejected: giving a quiet secondary action a fill to cast from promotes it to primary weight. The dialogs are where it shows, and they are where a device review should look.
- **The chip radius change (§6.11.2) is no longer isolated, and no longer the largest delta.** `999 → 4` now happens on `TypeBadge`, `TagChip`, `_RecognitionChip` and the chat bubble as well as on three chip classes. The judgement that produced it — a 2pt border meeting a shadow sliver at a non-orthogonal angle on a curved leading edge — applies identically to each, and it is now asserted per surface in `brutal_surface_test.dart` rather than argued once.
- **§6.11.3 is unaffected.** The switch thumb fix was never about style and nothing in this phase touched it.

---

## 7. Accessibility requirements

### 7.1 Contrast ratios — all computed, all arithmetic shown

Method: WCAG 2.1 relative luminance. For each sRGB channel `c ∈ [0,1]`: `c_lin = c/12.92` if `c ≤ 0.03928`, else `((c+0.055)/1.055)^2.4`. `L = 0.2126·R + 0.7152·G + 0.0722·B`. Ratio = `(L_lighter + 0.05) / (L_darker + 0.05)`.

**Luminance of every relevant colour, once:**

| Token | Hex | L | Derivation (channel → linear) |
|---|---|---|---|
| `canvas` light | `F8F4ED` | 0.90775 | 0.93871 / 0.90467 / 0.84690 |
| `paper` light | `FBF9F4` | 0.94793 | 0.96469 / 0.94731 / 0.90467 |
| `surfaceWarm1` light | `F0EAE0` | 0.82832 | 0.87142 / 0.82377 / 0.74536 |
| `surfaceWarm2` light | `E8E0D2` | 0.75123 | 0.80702 / 0.74536 / 0.64447 |
| `divider` light | `DDD2BD` | 0.65138 | 0.72308 / 0.64447 / 0.50881 |
| `stone` light | `7A6E61` | 0.16152 | 0.19460 / 0.15593 / 0.11951 |
| `graphite` light | `5A4F44` | 0.08182 | 0.10221 / 0.07818 / 0.05781 |
| `ink` light | `2D2520` | 0.01987 | 0.02628 / 0.01851 / 0.01444 |
| `accent` | `D97757` | 0.28636 | 0.69383 / 0.18452 / 0.09531 |
| `accentDeep` | `B04F2B` | 0.14996 | 0.43408 / 0.07818 / 0.02415 |
| `accentPressed` light | `BE6242` | 0.20073 | 0.51500 / 0.12208 / 0.05441 |
| `error` light | `A64A33` | 0.13241 | 0.38109 / 0.06851 / 0.03311 |
| `bone` light | `B5AB9E` | 0.41409 | 0.46192 / 0.40716 / 0.34197 |
| **`hardLight` on canvas** | `867F76` (composite) | 0.21297 | 0.55·`#281E14` over `#F8F4ED` |
| **`hardLight` on paper** | `878179` (composite) | 0.22183 | 0.55·`#281E14` over `#FBF9F4` — a control on `paper` gets its own composite |
| `canvas` dark | `1F1B16` | 0.01133 | 0.01371 / 0.01096 / 0.00800 |
| `paper`/`surfaceWarm1` dark | `2A2520` | 0.01921 | 0.02316 / 0.01851 / 0.01444 |
| `divider`/`surfaceWarm2` dark | `3A332C` | 0.03449 | 0.04231 / 0.03311 / 0.02518 |
| `stone` dark | `998D80` | 0.27382 | 0.31857 / 0.26634 / 0.21576 |
| `ink` dark | `E8E0D2` | 0.75123 | 0.80702 / 0.74536 / 0.64447 |
| `error` dark | `D9846F` | 0.32401 | 0.69383 / 0.23073 / 0.15897 |
| **`hardDark` on canvas** | `79746B` (composite) | 0.17621 | 0.45·`#E8E0D2` over `#1F1B16` |
| **`hardDark` on paper** | `807970` (composite) | 0.19497 | 0.45·`#E8E0D2` over `#2A2520` — a control on `paper` gets its own composite |

**Non-text boundaries (SC 1.4.11 — 3:1 required for UI component boundaries).**

The table is split because the comparison is not the same on both halves. A `BoxDecoration` border paints inside the box, on top of `decoration.color`, so an edge on a control is always adjacent to **that control's own fill** — not the page. Page-step rows below are therefore also page rows, because that is what a page step is filled with; slab rows are scored against the slab and against nothing else.

**Page step — outlined, ghost, field, chip at rest, sheet option, `TagChip` delete, OCR copy, and every disabled control:**

| Pair | Ratio | Verdict |
|---|---|---|
| `stone` light / `paper` light — brutal border | 0.99793 / 0.21152 = **4.72:1** | ✓ |
| `stone` light / `canvas` light | 0.95775 / 0.21152 = **4.53:1** | ✓ |
| `stone` light / `surfaceWarm2` light — disabled border | 0.80123 / 0.21152 = **3.79:1** | ✓ |
| `stone` dark / `paper` dark | 0.32382 / 0.06921 = **4.68:1** | ✓ |
| `stone` dark / `canvas` dark | 0.32382 / 0.06133 = **5.28:1** | ✓ |
| **`hardLight` / `canvas` light** | 0.95775 / 0.26297 = **3.64:1** | ✓ |
| **`hardLight` / `paper` light** | 0.99793 / 0.27183 = **3.67:1** | ✓ |
| **`hardDark` / `canvas` dark** | 0.22621 / 0.06133 = **3.69:1** | ✓ |
| **`hardDark` / `paper` dark** | 0.24497 / 0.06920 = **3.54:1** | ✓ |
| **`hardDark` / `ink` dark** (dark filled button's own fill) | 0.80123 / 0.22621 = **3.54:1** | ✓ |
| `focusLight` / `canvas` light — page-step ring | 0.95775 / 0.19996 = **4.79:1** | ✓ |
| `focusLight` / `paper` light — page-step ring | 0.99793 / 0.19996 = **4.99:1** | ✓ |
| `focusDark` / `canvas` dark — page-step ring | 0.33636 / 0.06133 = **5.48:1** | ✓ |
| `focusDark` / `paper` dark — page-step ring | 0.33636 / 0.06921 = **4.86:1** | ✓ |
| `stone` dark / `surfaceWarm2` dark — switch off-state thumb | 0.32382 / 0.08449 = **3.83:1** | ✓ |
| `canvas` dark / `accentDeep` — switch on-state thumb (dark) | 0.19996 / 0.06133 = **3.26:1** | ✓ |
| `accentDeep` / `paper` light — switch on track (light) | 0.99793 / 0.19996 = **4.99:1** | ✓ |

**Slab — the focus ring, measured against the fill it is painted on. Every row is `F'` on its own fill; this is the side SC 1.4.11 is scored on, because it is the side the ring physically touches.**

| Surface / mode | Ring | Fill | Ratio | Verdict |
|---|---|---|---|---|
| filled, light | `focusOnFillLight` `onAccent` (L 0.94793) | `accentDeep` (L 0.14996) | 0.99793 / 0.19996 = **4.99:1** | ✓ |
| destructive, light | `focusOnFillLight` `onAccent` (L 0.94793) | `error` (L 0.13241) | 0.99793 / 0.18241 = **5.47:1** | ✓ |
| chip selected, light | `focusOnFillLight` `onAccent` (L 0.94793) | `ink` (L 0.01987) | 0.99793 / 0.06987 = **14.28:1** | ✓ |
| switch on, light | `focusOnFillLight` `onAccent` (L 0.94793) | `accentDeep` (L 0.14996) | 0.99793 / 0.19996 = **4.99:1** | ✓ |
| filled, dark | `focusOnFillDark` `canvas` (L 0.01133) | `ink` (L 0.75123) | 0.80123 / 0.06133 = **13.06:1** | ✓ |
| chip selected, dark | `focusOnFillDark` `canvas` (L 0.01133) | `ink` (L 0.75123) | 0.80123 / 0.06133 = **13.06:1** | ✓ |
| switch on, dark | `focusOnFillDark` `canvas` (L 0.01133) | `accentDeep` (L 0.14996) | 0.19996 / 0.06133 = **3.26:1** | ✓ (marginal) |
| filled + pressed, light | `focusOnFillLight` `onAccent` | `ink` (the press fill) | 0.99793 / 0.06987 = **14.28:1** | ✓ |
| filled + pressed, dark | `focusOnFillPressedDark` `ink` (L 0.75123) | `canvas` (L 0.01133) | 0.80123 / 0.06133 = **13.06:1** | ✓ |

The two press rows are in the table because a keyboard user holding Space is focused *and* pressed at once, and the dark press fill is `canvas` — which is the dark ring. Without `focusOnFillPressedDark` a dark button rings itself in its own ring colour. The light pair needs no flip: `onAccent` is 14.28:1 on the light press fill.

**Slab — the resting edge, `E` = `edgeOnFill` on the same fills.** SC 1.4.11's 3:1 is not owed here; a resting edge is not the focus indicator. What it owes is being visible, and this is the row that says how visible.

| Surface / mode | Resting edge | Fill | Ratio | Verdict |
|---|---|---|---|---|
| filled, light | `edgeOnFillLight` `bone` (L 0.41409) | `accentDeep` | 0.46409 / 0.19996 = **2.32:1** | ✓ visible |
| destructive, light | `edgeOnFillLight` `bone` | `error` | 0.46409 / 0.18241 = **2.54:1** | ✓ visible |
| chip selected, light | `edgeOnFillLight` `bone` | `ink` | 0.46409 / 0.06987 = **6.64:1** | ✓ |
| filled, dark | `edgeOnFillDark` `bone` (L 0.08182) | `ink` | 0.80123 / 0.13182 = **6.08:1** | ✓ |
| destructive, dark | `edgeOnFillDark` `bone` | `error` | 0.37401 / 0.13182 = **2.84:1** | ✓ visible |
| switch on, **resting** | `stone` — *not* `E`, see §7.6 | `accentDeep` | 0.21152 / 0.19996 = **1.06:1** light · 0.32382 / 0.19996 = **1.62:1** dark | ✗ known gap |

**The light filled button's resting edge, before and after.** `stone` on `accentDeep` = 0.21152 / 0.19996 = **1.06:1** — a 2pt border that drew nothing, on the control the whole hard-edge language rests on. `edgeOnFillLight` `bone` on the same fill = 0.46409 / 0.19996 = **2.32:1**. Ring to edge is then 2.15:1 apart in light (0.99793 / 0.46409) and 2.15:1 in dark (0.13182 / 0.06133) — a step rather than an inversion, and deliberately so; the reasoning, and the `ink` alternative that fails at 1.00:1 on the selected chip, is §6.10.

**Three rows corrected after review.** The `hardLight`/`paper` and `hardDark`/`paper` rows were each computed against the *canvas* composite while quoting the *paper* background. A shadow's composite depends on what it is composited onto, so each needs its own: the two `… on paper` rows above give them. Measured: `hardLight`/`paper` is **3.67:1** (this table previously said 3.80) and `hardDark`/`paper` is **3.54:1** (previously 3.27, which is the value belonging to the dark filled button's own `ink` fill). Both still clear 3:1 comfortably; only the arithmetic was wrong. The third is the whole slab block above, which this document previously did not have: it scored the ring against the page and called the resulting 1.00:1 "irrelevant". See §6.10.

**One ring row that is conformant but weak, stated so a screenshot does not look like a bug:** the light filled button's ring against the **page** is `onAccent` on `canvas` = 0.99793 / 0.95775 = **1.04:1**. The outer edge merges with the cream page. SC 1.4.11 scores the adjacent fill, not the page, and no page step that clears 3:1 against `accentDeep` exists without itself being page-coloured. §6.10 carries the full statement.

**Five pre-existing failures this spec fixes, stated so a reviewer can check the claim:**

| Pair (as shipped today) | Ratio | Status |
|---|---|---|
| `divider` light / `paper` light — the 0.5pt hairline on a control boundary | 0.99793 / 0.70138 = **1.42:1** | ✗ fails 3:1 |
| `divider` dark / `paper` dark — the 1.0pt hairline on a control boundary | 0.08449 / 0.06921 = **1.22:1** | ✗ fails 3:1 |
| `paper` dark / `surfaceWarm2` dark — switch off-state thumb (as shipped) | 0.08449 / 0.06921 = **1.22:1** | ✗ fails 3:1 |
| `accent` / `paper` light — the existing 1.5pt focus ring | 0.99793 / 0.33636 = **2.97:1** | ✗ fails 3:1 |
| `accent` / `canvas` light — the existing focus ring on canvas | 0.95775 / 0.33636 = **2.85:1** | ✗ fails 3:1 |

**The §2.5 reversal: `surfaceEdge` on every fill a read-only surface uses.**

No fill changed, so every text ratio below is carried over unchanged. What is new
is the **edge**, because the edge is scored against its own fill (§6.10). This is
the full measured set; operands are `L + 0.05`.

Luminances used that are not in the table above: `errorSoft` light `#F3E0DC` =
**0.775436** (0.89623 / 0.74542 / 0.71574), `errorSoft` dark `#4A2E28` =
**0.035628** (0.06847 / 0.027323 / 0.021194), `codeBg` dark `#161210` =
**0.0064089** (0.0080135 / 0.0060553 / 0.0051860).

| Surface / mode | Fill | Edge | Ratio | Verdict |
|---|---|---|---|---|
| card, light | `paper` | `surfaceEdgeLight` | 0.99793 / 0.21152 = **4.72:1** | ✓ |
| card, dark | `paper` | `surfaceEdgeDark` | 0.32382 / 0.06921 = **4.68:1** | ✓ |
| dialog / sheet, light | `paper` | `surfaceEdgeLight` | **4.72:1** | ✓ |
| dialog / sheet, dark | `paper` | `surfaceEdgeDark` | **4.68:1** | ✓ |
| badge (`TypeBadge`), light | `badgeBg` `surfaceWarm2` | `surfaceEdgeLight` | 0.80123 / 0.21152 = **3.79:1** | ✓ |
| badge, dark | `badgeBg` | `surfaceEdgeDark` | 0.32382 / 0.08449 = **3.83:1** | ✓ |
| tag (`TagChip`), light | `paper` | `surfaceEdgeLight` | **4.72:1** | ✓ |
| tag, dark | `paper` | `surfaceEdgeDark` | **4.68:1** | ✓ |
| recognition chip, light | `surfaceWarm1` | `surfaceEdgeLight` | 0.87832 / 0.21152 = **4.15:1** | ✓ |
| recognition chip, dark | `surfaceWarm1` | `surfaceEdgeDark` | **4.68:1** | ✓ |
| processing banner, light | `surfaceWarm2` | `surfaceEdgeLight` | **3.79:1** | ✓ |
| processing banner, dark | `surfaceWarm2` | `surfaceEdgeDark` | **3.83:1** | ✓ |
| ingest banner, running | as banner | `surfaceEdge(isDark)` | **3.79 / 3.83:1** | ✓ |
| ingest banner, **paused** | `surfaceWarm1` | `surfaceEdge(isDark)` | **4.15 / 4.68:1** | ✓ |
| error banner, light | `errorSoft` | `surfaceEdgeLight` | 0.82544 / 0.21152 = **3.90:1** | ✓ |
| error banner, dark | `errorSoft` | `surfaceEdgeDark` | 0.32382 / 0.08563 = **3.78:1** | ✓ |
| chat bubble, light | `surfaceWarm1` | `surfaceEdgeLight` | **4.15:1** | ✓ |
| chat bubble, dark | `surfaceWarm1` | `surfaceEdgeDark` | **4.68:1** | ✓ |
| related-links card, light | `paper` | `surfaceEdgeLight` | **4.72:1** | ✓ |
| related-links card, dark | `paper` | `surfaceEdgeDark` | **4.68:1** | ✓ |
| **OCR block, light** | `codeBg` #1F1B16 | `surfaceEdgeLight` | 0.21152 / 0.06133 = **3.45:1** | ✓ tightest in the app |
| **OCR block, dark** | `codeBg` #161210 | `surfaceEdgeDark` | 0.32382 / 0.05641 = **5.74:1** | ✓ |

**Snackbar — a slab, so it takes the slab edge.**

| Surface / mode | Fill | Edge | Ratio | Verdict |
|---|---|---|---|---|
| snackbar, light | `ink` | `edgeOnFillLight` `bone` | 0.46409 / 0.06987 = **6.64:1** | ✓ |
| snackbar, dark | `ink` | `edgeOnFillDark` `bone` | 0.80123 / 0.13182 = **6.08:1** | ✓ |
| snackbar, light | `ink` | ~~`surfaceEdgeLight`~~ | 0.21152 / 0.06987 = **3.03:1** | ✗ **rejected** |
| snackbar, dark | `ink` | ~~`surfaceEdgeDark`~~ | 0.32382 / 0.80123 = **0.40:1** | ✗ **rejected** |

The two crossed rows are the reason this is the one theme block that does not
take `surfaceEdge`. A snackbar fills with `ink` in **both** modes, so in dark
mode the box is a *cream* fill and `stone` — the palette's mid-warm grey — lands
at 0.40:1 against it. Had the reversal copied the dialog's rule instead of
applying §6.10, every snackbar in dark mode would have shipped with no border.
This is the clearest single argument for §6.10's page-step/slab split surviving
the reversal intact.

**Text on the reversal's surfaces — unchanged, and recomputed anyway.**

| Pair | Ratio | Verdict |
|---|---|---|
| `badgeText` / `badgeBg` light (11pt/600) | 0.80123 / 0.13182 = **6.08:1** | ✓ |
| `badgeText` / `badgeBg` dark | 0.46409 / 0.08449 = **5.49:1** | ✓ |
| `tagText` / `paper` light (11pt/600) | **4.72:1** | ✓ |
| `tagText` / `paper` dark | **4.68:1** | ✓ |
| `ink` / `surfaceWarm1` — chat bubble, light (16pt) | 0.87832 / 0.06987 = **12.57:1** | ✓ |
| `ink` / `surfaceWarm1` — chat bubble, dark | 0.80123 / 0.06921 = **11.58:1** | ✓ |
| `ink` / `surfaceWarm2` — banner, light (15pt/500) | 0.80123 / 0.06987 = **11.47:1** | ✓ |
| `ink` / `surfaceWarm2` — banner, dark | 0.80123 / 0.08449 = **9.48:1** | ✓ |
| `graphite` / `surfaceWarm2` — ingest ETA line, light (13pt) | 0.80123 / 0.13182 = **6.08:1** | ✓ |
| `codeText` / `codeBg` light — OCR mono, 13pt | 0.80123 / 0.06133 = **13.06:1** | ✓ |
| `codeText` / `codeBg` dark — OCR mono, 13pt | 0.80123 / 0.05641 = **14.20:1** | ✓ |
| `paper` / `ink` — snackbar text, light (14pt) | **14.28:1** | ✓ |
| `canvas` / `ink` — snackbar text, dark | **13.06:1** | ✓ |
| `onAccent` / `paper` — OCR copy button label (outline) | **14.28:1** | ✓ |

**One PRE-EXISTING failure on a surface the reversal touched, reported and not
fixed.** `error` on `errorSoft` in **dark** — the home error banner's 15pt/500
message — is 0.37401 / 0.08563 = **4.37:1**, below SC 1.4.3's 4.5:1. It is **not**
a regression: the banner's fill is untouched and `error`/`errorSoft` are both out
of scope for a visual restyle (§9 forbids a palette change), so the reversal had
no hand in it. It is listed because the reversal is the moment anyone will look
at that banner closely, and a reviewer should not have to diff two commits to
find out this was already there. The light-mode row is 4.53:1 and passes.

**Two more that this spec shipped before it fixed them, recorded because they were live in the tree as built and are the reason §6.10 exists:**

| Pair (as built, before the §6.10 correction) | Ratio | Status |
|---|---|---|
| `focusLight` / `accentDeep` — ring on the light filled button's own fill | 0.19996 / 0.19996 = **1.00:1** | ✗ SC 2.4.7, no indicator at all |
| `stone` / `accentDeep` — the resting 2pt edge on that same fill | 0.21152 / 0.19996 = **1.06:1** | ✗ not a boundary |

The hairline numbers are the reason the border **colour** had to change and not just the weight. Thickening `divider` from 0.5pt to 2pt at the same colour would still be 1.42:1 — thickness is not contrast. `stone` was chosen because it already exists in both `SiftColors` instances, so the fix costs no new colour in either mode.

**Text (SC 1.4.3 — 4.5:1 required below 18.66px bold / 24px). All button labels are 15pt/600 (`SiftType.buttonLabel`, `app_theme.dart:174-178`), so 4.5:1 applies to every one.**

| Pair | Ratio | Verdict |
|---|---|---|
| `onAccent` / `accentDeep` — filled label, light rest | 0.99793 / 0.19996 = **4.99:1** | ✓ |
| `onAccent` / `accentPressed` — filled label, **current** pressed | 0.99793 / 0.25073 = **3.98:1** | ✗ **fixed by this spec** → `onAccent` / `ink` = 0.99793 / 0.06987 = **14.28:1** |
| `canvas` / `ink` — filled label, dark rest and pressed | 0.80123 / 0.06133 = **13.06:1** | ✓ |
| `ink` / `paper` — outlined label | 0.99793 / 0.06987 = **14.28:1** | ✓ |
| `ink` / `surfaceWarm1` — outlined label, light pressed | 0.87832 / 0.06987 = **12.57:1** | ✓ |
| `ink` / `surfaceWarm2` — outlined label, dark pressed | 0.80123 / 0.08449 = **9.48:1** | ✓ |
| `ink` / `paper` light — ghost label, light rest | **14.28:1** | ✓ |
| `onAccent` / `error` light — destructive label | 0.99793 / 0.18241 = **5.47:1** | ✓ |
| `canvas` / `error` dark — destructive label | 0.37401 / 0.06133 = **6.10:1** | ✓ |
| `ink` / `paper` — input text | **14.28:1** | ✓ |
| `stone` / `paper` — input hint (15px) | **4.72:1** | ✓ |
| `canvas` / `ink` — selected chip label (light) | **13.06:1** | ✓ |
| `ink` / `paper` — unselected chip label (light) | **14.28:1** | ✓ |

**The ghost's PRESSED label — measured against the fill it is drawn on, not against the page.**

This block replaces two rows that were scored against `canvas` in both modes. That was a genuine arithmetic error, not a rounding one, and it shipped as a live SC 1.4.3 failure. The §1 "fill-agnostic" argument covers a hard shadow, whose offset hides the near edges; it does **not** cover a label drawn on top of a fill, which is the pressed ghost's entire signal. At HEAD before this correction, a pressed ghost measured:

| Pair as it actually rendered | Ratio | Status |
|---|---|---|
| light, default label — `accentDeep` on the `surfaceWarm1` fill | 0.87753 / 0.19996 = **4.39:1** | ✗ fails 4.5:1 |
| light, `Skip` / `Ask` — `stone` on `surfaceWarm1` | 0.87753 / 0.21153 = **4.15:1** | ✗ fails 4.5:1 |
| dark, default label — `accent` on the `surfaceWarm2` fill | 0.33633 / 0.08449 = **3.98:1** | ✗ fails 4.5:1 |
| dark, `Skip` / `Ask` — `stone` on `surfaceWarm2` | 0.32382 / 0.08449 = **3.83:1** | ✗ fails 4.5:1 |

As shipped, against the fills the widget now actually paints. **The operands below are `L + 0.05`, not raw `L`** — the ratio is that quotient directly, and reading them as luminances and adding 0.05 again double-counts it:

| Pair | `L_lighter + 0.05` / `L_darker + 0.05` | Verdict |
|---|---|---|
| light pressed — default `accentDeep` on the **`canvas`** fill | 0.95775 / 0.19996 = **4.79:1** | ✓ |
| light pressed — dimmed `stone` on the **`canvas`** fill | 0.95775 / 0.21152 = **4.53:1** | ✓ |
| dark pressed — default `ink` on the **`paper`** fill | 0.80123 / 0.06921 = **11.58:1** | ✓ |
| dark pressed — dimmed `stone` on the **`paper`** fill | 0.32382 / 0.06921 = **4.68:1** | ✓ |

**The `stone` rows are the binding ones, not the defaults.** Two call sites pass a `Text` whose own `style.color` is `stone` — `onboarding_screen.dart:69` (`Skip`) and `widgets.dart:320` (`Ask your memory instead`) — and `DefaultTextStyle.merge` only *supplies* a colour to a `Text` that has none of its own. A `Text` that sets one keeps it, in every state, so those two sites are at 4.53:1 / 4.68:1 on the pressed fill and the other ten ghost sites are at 4.79:1 / 11.58:1. Both label colours are `buttonLabel` 15pt/600 and both owe 4.5:1; the `stone` pair is the tighter of the two and is the one that would fail first.

Why those two fills, both verified rather than assumed:

- **Light → `canvas`.** `surfaceWarm1` is ruled out by the 4.39:1 above. `canvas` clears both labels. (It is the page, so the *label* change to `accentDeep` is what carries the press — the fill alone would not.)
- **Dark → `paper`.** `surfaceWarm2` is ruled out by the `stone` row (3.83:1). `canvas` clears both labels comfortably, but it **is** the dark page, so a `canvas` press would change nothing at all and leave the fill as the only press signal, against §7.4. `paper` is the one step that both lifts the press visibly and clears both labels.

`brutal_button_test.dart` recomputes all four of these from the mounted, pressed widget — reading the rendered `RichText` colour and the rendered `BoxDecoration` fill — rather than restating the numbers, so a revert fails the suite instead of quietly restoring a 3.83:1 label.

**Disabled (SC 1.4.3 exempt — "text that is part of an inactive user interface component").**

`stone` on `surfaceWarm2` = **3.79:1**. Below 4.5:1 and **conformant**, per the explicit inactive-component exemption. It is also above 3:1, so the disabled control's shape remains identifiable (SC 1.4.11, in the table above). Do not change it.

**One documented sub-3:1 shadow pair, not a failure:** `hardDark` on a saturated `error` fill in dark mode is 0.37401 / 0.22621 = **1.65:1**. Per the §1 derivation the shadow's visible sliver sits on `canvas` (3.69:1) and its near edges are hidden behind the control, so the pair is never rendered. It is listed rather than omitted because a reviewer screenshotting a dark destructive button's bounding box will see the number and should know it was considered.

### 7.2 Minimum touch targets

- `BrutalButton` filled / outline / destructive: **48dp** total height including the 2dp border (`SiftSpacing.btnH`). Interior 44dp.
- `BrutalButton.text`: **40dp**, matching the existing `textButtonTheme` minimum (`app_theme.dart:724`) so the 12 ghost call sites' row heights do not change.
- `SiftBrutalField`: 48dp (`settings_screen.dart:665`) or 52dp (`chat_screen.dart:683`, `shopping_list_screen.dart:155`) — both unchanged.
- `SiftBrutalChip`: 32dp content height. **This is below 48dp and is a documented exception**, not an oversight. It matches the app's existing `SiftSpacing.chipH` and the 3 chip classes already ship at 32dp. WCAG 2.2 SC 2.5.8 (Target Size Minimum, 24×24 CSS px) is met at 32dp; the 44×44 AAA criterion (2.5.5) is not, and was not met before this change either. The horizontal row spacing (8dp between chips) means adjacent targets are separated, which SC 2.5.8's "spacing" exception also permits. **Do not enlarge chips in this spec** — it would reflow three screens and is a layout change (§9).
- `Switch`: Material default ≥48dp; `materialTapTargetSize` left at default. Note that `_flatSwitch` sits as a `trailing` in a tappable `_flatRow`/`_checklistStep`, so its effective target is larger still.
- `TagChip` delete target: 40×40 (`widgets.dart:80-97`), unchanged.
- **OCR copy button: 36dp** (`detail_screen.dart:365-369`), overriding `BrutalButton`'s 48dp `height` default. **This is below 48dp and is a documented exception**, not an oversight. It is not a regression: the Material `TextButton` it replaced already carried `minimumSize: Size(0, 36)`, and 36 is carried over unchanged so the OCR block does not grow (§4.16). WCAG 2.2 SC 2.5.8 is met at 36dp; the 44×44 AAA criterion (2.5.5) is not, and was not met before this change either. The 40x40 icon box sits inside it, and the button is the only target in the block, so the 24px minimum is clear in both axes. **Do not enlarge it in this spec** — that would grow the OCR block and is a layout change (§9).

### 7.3 Focus-visible

- 2dp ring in the control's own box, replacing that box's resting edge in place (§5.4). The colour is `SiftBrutal.focus(isDark)` on a **page step** and `SiftBrutal.focusOnFill(isDark: isDark, pressed: …)` on a **slab**, whose resting edge is `SiftBrutal.edgeOnFill(isDark)` — page step or slab is decided by what the box is filled with, not by which widget it is (§6.10).
- Present on keyboard focus, switch access, and any focusable control. **Absent on tap.** Implement with an explicit `Focus` widget and `onFocusChange` (as specced in §5.2), not with the theme's `focusColor` — Flutter's `focusColor` fires on pointer focus too, which would flash a ring on every tap.
- `app_theme.dart:590` sets `focusColor: accent @ 0.18`. `BrutalButton` must set `focusColor: Colors.transparent` locally so no Material wash appears under the hard ring. The theme value stays for Material components, of which the app now has **none** — §4.16 retired the last one.
- All figures in §7.1. Every slab clears 3:1 against its own fill in both modes; the tightest is the dark switch track at 3.26:1. On a page step both modes clear 3:1 with margin. One ring is weak against the page — the light filled button at 1.04:1, §6.10 — which is conformant because 1.4.11 scores the adjacent fill, and is stated rather than hidden.
- Enter and Space must reach the control, not just Tab. A `GestureDetector` is announced and reachable but is inert to a keyboard; `brutalActivate` (`brutal_activate.dart`) wraps every brutal control in the `Actions` ancestor that Material's `InkWell` used to supply, and is what makes the ring mean something for a keyboard user. A ring that cannot be acted on is a SC 2.4.7 failure wearing a pass.
- **After the reversal this section covers more controls, not fewer.** The OCR copy button (§4.16) gained the ring it previously only approximated, the `TypeBadge` / `TagChip` / `_RecognitionChip` bodies gained **no** focus machinery at all because they are not operable (§4.12), and the six rows inside hard containers keep the rings they had (§2.5). The invariant is unchanged: **a focusable thing has a ring that clears 3:1 against its own fill; a non-focusable thing has no ring machinery to get wrong.**

### 7.4 The press effect is never the sole state indicator

Restated as an acceptance criterion: with `MotionTokens.reduced = true`, pressing any brutal control must still produce an observable change with no motion. §4.1's fill inversion is that change. Verify by toggling the OS reduce-motion setting and pressing a filled button, an outlined button, a chip, and a destructive button.

### 7.5 Nothing else in this spec affects accessibility

Layout, spacing, copy, typography, and navigation are unchanged (§9), so text size, reflow, reading order, and hit order are all unaffected. The only semantic change is `FilledButton` → a custom widget, which is why §5.3 is mandatory rather than advisory.

### 7.6 Known remaining gaps

Recorded, not fixed. Line references in this subsection are **post-migration** (§2 convention).

1. **The Material button themes still carry the pre-migration focus side.** `app_theme.dart:733-738` — `filledButtonTheme`'s focus `side` is a 1.5pt `accent`, which is 2.97:1 on `paper` and 2.85:1 on `canvas`; `app_theme.dart:762-768` — `outlinedButtonTheme`'s is `accent` at 1.5pt, 2.97:1 on `paper`. Neither clears 3:1, and neither is read by anything in the app: all 29 migrated call sites use `BrutalButton`, which resolves its own border from `SiftBrutal` and never touches the theme. These blocks are the fallback for a Material button a dependency or a future screen introduces, and §5.5 says to leave them in place — so the sub-3:1 side is still in the file. If that fallback is ever actually used, it needs the §6.10 rule, not `focus`.
2. **The switch ON track's resting outline is still `stone`.** 1.06:1 in light, 1.62:1 in dark against the `accentDeep` track — the same defect as the light filled button's resting edge, on the one slab the `switchTheme` does not give an `E` to. `app_theme.dart:689-695` only branches the outline on `focused`; a selected-and-unfocused track falls through to `s.stone`. The focused state is correct (3.26:1 dark, 4.99:1 light) because focus is the indicator. Fixing it means teaching `trackOutlineColor` a third branch, which is why it was left out of the §6.10 change rather than slipped into it.
3. **`brutal_button.dart:152-155` prints its own arithmetic in a form that invites a misread.** The block quotes `dark ink / paper 0.80120 / 0.06920 = 11.58:1`. The value is right — those operands are `L + 0.05` and the quotient is the WCAG ratio — but the comment does not say so, and a reader who takes them for raw luminances and adds 0.05 again gets 7.14:1, which is wrong. The code has no behaviour to fix; only the comment's labelling. §7.1's ghost-pressed table now labels its operand column `L_lighter + 0.05` for the same reason.
4. **NEW: the dark-mode error banner is 4.37:1** — `error` on `errorSoft`, 15pt/500, below SC 1.4.3's 4.5:1. Pre-existing and untouched by the §2.5 reversal, which changed the banner's *edge* and not its fill. Recorded here as well as in §7.1 because §7.6 is where a reviewer looks for known defects, and this one is now on a hard-edged surface where the 2pt border makes the box look more finished than its text is legible. Fixing it is a palette decision, not a restyle decision.
5. **NEW: a dialog carries no hard shadow.** §4.11 item 4 and §10.1 item 1. A `Material` has no `boxShadow`, so `elevation: 0` removes the blur and nothing replaces it. Shipped deliberately, listed here so nobody reads the absence as an oversight.

### 7.7 Fixed since this spec was written

The gap §7.6 used to carry as its third item was the chat send circle. It is fixed. The reasoning is kept here because it is the reusable part — but **it is not an open defect** and must not be read as one.

**What it was.** `SiftSendCircle` (`chat_screen.dart:738`, post-migration) was a bare `GestureDetector` + `AnimatedScale` + `AnimatedContainer` with no `Focus`, no `Semantics(button:)`, no `brutalActivate`, and no hard edge. It was therefore not reachable by keyboard activation, had no focus ring, and announced as a plain object rather than a button. It was a §2.5 exclusion ("circular icon buttons keep their existing press-scale"), and it was the one interactive element in the app that was not covered by any state table in §4. Recorded because §2.5's exclusion rationale is about the *shape* — a hard cast shadow fights a circle's curvature — and says nothing about focus, which is why the exclusion over-reached.

**What it is now.** Focusable, keyboard-activatable, ringed, and announced as a button: `Focus` + `brutalActivate` + `Semantics(button: true, enabled: …, label: 'Send message')`. §2.5's *shape* exclusion is honoured exactly — the press-scale, the fill, and the circle are untouched. The ring is a 2pt `BoxDecoration` border on the same circle, which follows the curve rather than boxing it in, and it resolves by the §6.10 page-step/slab rule decided by the **fill**, not the shape: enabled, the `accentDeep` fill is a slab and takes `focusOnFill`; disabled, `surfaceWarm2` is a page step and takes plain `focus`. Scored against its own fill that is **4.99:1** light enabled, **3.26:1** dark enabled, **4.01:1** light disabled, **3.98:1** dark disabled — clearing SC 1.4.11's 3:1 in all four, the dark enabled row being the same `canvas`-on-`accentDeep` figure as the switch ON track (§7.1).

The widget is public (`SiftSendCircle`, formerly `_SendCircle`) so it can be mounted and tested on its own rather than by wrapping the whole chat screen around it; `test/chat_send_circle_test.dart` locks the focus, the ring, the keyboard activation, and all four contrast ratios. One behaviour note: `brutalActivate` is handed `null` while disabled, so Enter and Space are swallowed rather than firing a send the pointer is not allowed to make.

---

## 8. Rollout order

Five phases. Each is independently reviewable and shippable. **A phase that reads as noise is reverted, not compensated for by the next phase.** If Phase 1 fails, do not proceed to Phase 2 hoping the combination works — a full-restyle decision is a different spec.

> **These five rows are history, kept verbatim.** Their gates, counts and the `23/23` in them describe the tree **as it stood during that phase**, and two of them ("every one of the 12 §2.5 exclusions is confirmed still warm", "paper = read, hard = operate") record decisions that Phase 6 **reversed** — see §1, §2.5 and §4.9–§4.16. The current counts are in §8.1. Nothing below has been edited to pretend otherwise.

| Phase | Contents | Files touched | Review gate |
|---|---|---|---|
| **1 — Tokens + buttons** | `brutal_tokens.dart`; `SiftBrutalButton` widget; `rControl` in `SiftRadii`; `switchTheme` untouched. Migrate all **29** Material button call sites. `destructive` variant exists but is adopted at **one** site (`settings_screen.dart:1030`). | `theme/brutal_tokens.dart`, `theme/app_theme.dart` (radii + 3 comments), `widgets/brutal_button.dart`, 11 call-site files | Light **and** dark, on Detail (worst case for §6.1), Settings, and Onboarding. Confirm: the hard shadow is visible in dark (§6.4); the 4dp chip slack is not yet relevant; TalkBack reaches all 29 in order (§6.5); reduced-motion press still reads (§7.4). `flutter analyze` clean, `23/23` tests. |
| **2 — Inputs** | `SiftBrutalField`; all **5** sites. Focus border replaces `accent`; three sites gain a focus state they never had. | `widgets/brutal_field.dart`, 5 screen files | Type into each field, light and dark. Confirm no height change (48/52 preserved), the focus border is clearly visible, and Settings' key field still saves on every keystroke (`_saveSettings` untouched). |
| **3 — Chips, filters, switches** | `SiftBrutalChip` for all 3 classes (radius 999 → `rControl`, +2pt border, +hard shadow, +selected fill inversion). `switchTheme` rewrite with the dark thumb fixes. `TagChip` delete target gets a focus ring. | `widgets/brutal_chip.dart`, `home_screen.dart`, `actions_history_screen.dart`, `chat_screen.dart`, `settings_screen.dart`, `app_theme.dart`, `widgets.dart` | **The highest-scrutiny phase** — see §6.11.2 (pill → 4pt radius is the biggest shape change in the spec) and §6.11.3 (switch thumbs are a behaviour fix). Confirm: no chip row reflows in `actions_history` or `chat_screen`; no chip clips in `home_screen`'s 40dp slot; the switch thumb is visible in both states in dark mode. |
| **4 — Dialogs and bottom sheet** | Action rows inside the 9 `showDialog`/`AlertDialog` sites get brutal buttons (mostly already done in Phase 1). The bottom sheet's `_SourceOption` pair becomes brutal: 2pt border, `rControl`, hard shadow, press. **Sheet and dialog chrome stay `rSheet` 24 / `rCard` 20 with no hard border or shadow** — they are containers, not controls (§2.5). | `widgets/bottom_sheet.dart` | Open every dialog and the capture sheet, light and dark. Confirm the chrome is visibly *unchanged* from Phase 1 — if the sheet itself grew a hard edge, that is a Phase 4 failure. |
| **5 — Coherence review** | No new styling. Audit the whole app against §1 and §2.5. | none (read-only) | Run the mechanical checks: (a) `grep -n "BoxShadow" lib/` returns hits **only** in `app_theme.dart` and `brutal_tokens.dart` (§6.3); (b) every one of the 12 §2.5 exclusions is confirmed still warm; (c) all offsets equal `SiftBrutal.offset`; (d) no `blurRadius > 0` on any brutal shadow; (e) no `BackdropFilter` / `Shader` / `RepaintBoundary` added (§6.7); (f) `flutter analyze` clean and `23/23` tests; (g) walk all 8 screens in both modes and confirm the grammar holds: paper = read, hard = operate. |

**Rollback.** Each phase is a separate commit and independently revertible. Phases 1 and 2 are the ones worth keeping even if 3–5 are abandoned; a spec that lands only buttons and inputs is already a net accessibility improvement, because it fixes the hairline-boundary and focus-ring contrast failures in §7.1.

### 8.1 Phase 6 — the §2.5 reversal (shipped)

Phases 1–5 are history. This is what actually shipped on top of them, and it is
recorded here rather than in a new document because the thing a reviewer most
needs is the diff *against the decision above*, and that diff is only legible in
one place.

| | |
|---|---|
| **Contents** | Cards, dialog chrome, sheet chrome, snackbars, chat bubbles, the OCR block, `TypeBadge` / `TagChip` / `_RecognitionChip`, all three banners, the three floating bars, Detail's web-result tile, `RelatedLinksStrip`, the onboarding mock panel, skeletons. Plus `SiftBrutal.surfaceEdge`, `brutalEdge(...)`, and the migration of the OCR copy button to `BrutalButton.outline`. |
| **Files** | `theme/brutal_tokens.dart`, `theme/app_theme.dart`, `widgets/brutal_chip.dart`, `widgets/widgets.dart`, `widgets/ingest_banner.dart`, `widgets/skeleton.dart`, `widgets/bottom_sheet.dart`, `widgets/chat_atoms.dart`, `screens/home_screen.dart`, `screens/detail_screen.dart`, `screens/onboarding_screen.dart`, `test/brutal_surface_test.dart`, `test/brutal_dialog_test.dart` |
| **Review gate — passed** | `dart format --set-exit-if-changed`: 0 changed. `flutter analyze`: the 5 pre-existing issues, 0 new. `flutter test` on the whole suite except `delete_everything_test.dart`: **399/399**. The six original `brutal_*` files plus the new one: **106/106**. `delete_everything_test.dart --plain-name "Settings removes the model first, then resets the screen"`: pass. |
| **Deliberately NOT done** | No dialog hard shadow (§4.11, item 4). No hard shadow on a `TagChip` / `TypeBadge` / `_RecognitionChip` body (§4.12). No 2pt row separators (§4.15). No change to the six row-inside-a-container exclusions (§2.5). No assistant bubble (§4.14). The pre-existing 4.37:1 `error`-on-`errorSoft` dark-mode banner text (§7.1), which is a palette matter and out of scope for a visual restyle. |

---

## 9. Explicit non-goals

**Amended for the §2.5 reversal.** Two rows below are no longer true as written;
they are corrected rather than deleted, because the correction is the point.

- **No layout change.** No `SiftSpacing` value changes. No new `Padding`,
  `SizedBox`, `Row`, `Column`, or `Wrap`. No grid, breakpoint, or inset change.
  The corner-radius delta (20 → 4, 24 → 4, 12 → 4) is a corner treatment, not
  layout, and a `Border.all` paints inside the existing bounds. `BrutalButton`
  keeps the exact heights the Material themes already imposed (48 / 40), and the
  OCR copy button keeps the 36dp its `minimumSize` already imposed.
- **No spacing change.** `SiftSpacing` is untouched. `SiftRadii` gains one
  constant and changes no existing one.
- **No copy change.** Not one string literal. `test/screenshot_analyzer_test.dart`
  asserts on privacy and onboarding copy across seven files; every one of those
  assertions passes unchanged. The privacy paragraphs in `privacy_gate.dart`,
  `about_dialog.dart`, `chat_screen.dart`, `onboarding_screen.dart` and
  `settings_screen.dart` were not touched, reflowed, or moved.
- **No typography change.** `SiftType` is untouched. The serif assistant voice
  and the sans chrome split are untouched. No font size, weight, letter-spacing,
  or family change — including on the OCR copy button, which keeps the 12pt
  `metaLabel` the Material `TextButton` gave it.
- **No canvas or paper colour change.** `SiftColors.canvas`, `paper`,
  `surfaceWarm1`, `surfaceWarm2` are unchanged in both instances. **No read-only
  surface changed its fill**, which is why no body-text ratio needed re-auditing.
- **No accent change.** `accent`, `accentDeep`, `accentSoft`, `accentPressed`
  are all unchanged. `accentPressed` is retired *for brutal buttons* only and
  remains in the palette. The card's selected edge keeps its existing `accent`.
- **No soft shadow token removed.** `SiftElevation.l1`–`l5` and `l4Dark` keep
  their exact alpha, offset and blur, and §9 requires it: the ramp is for
  non-surface work. `card()` and `sheet()` are kept as superseded helpers rather
  than deleted. **What changed is that no visible surface reads them**, which is
  asserted by a test rather than by review.
- **No navigation change.** No route, tab, deep-link, or back-behaviour change.
  `IndexedStack` untouched.
- **No new pub dependencies.** The reversal uses only `flutter/material.dart` and
  existing local imports. This preserves the DESIGNSTATE.md:17 constraint.
- **No animation beyond the press translation.** No scale, no rotation, no
  spring, no bounce, no new curves, no new `AnimationController`. The press reuses
  `MotionTokens.press` / `pressRelease` / `easeOutCubic` and adds no duration of
  its own. Nothing loops. The only idle motion in the app remains the mark pulse
  and the streaming caret — and the reversal touched neither, which is asserted.
- **No haptics added.** The press now carries its own feedback.
  `MotionTokens.canHaptic` calls stay exactly where they are.
- **No change to `MotionTokens`.** Not one line.
- ~~**No change to the 12 §2.5 exclusions**~~ **Reversed.** Nine of them moved
  into scope and one more was added (§2.5, §4.9–§4.16). The remaining rows still
  stand, and the list is still the restraint mechanism — just a shorter one, and
  now about *rows inside a hard container* rather than about containers
  themselves.
- **No `BrutalTheme`.** The change is deliberately *not* a `ThemeExtension` and
  *not* a `ThemeData` switch for surfaces. The five theme blocks that were
  updated (`cardTheme`, `snackBarTheme`, `bottomSheetTheme`, `dialogTheme`,
  `dividerTheme`) are updated to the same tokens the widgets read, not to new
  values; a theme switch would make it impossible to hold the grammar line
  against future code, which is the whole point of §2.5.
- **No goldens, no `toImage`.** No pixel test was added. A previous attempt at
  this work hung the whole suite on 300s+ timeouts; every assertion in the new
  `brutal_surface_test.dart` is a property read off a widget tree or a source
  file.

---

## 10. Open questions and UNVERIFIED items

1. **Flutter SDK version — UNVERIFIED in this session.** `.metadata:7` pins revision `ee80f08bbf97172ec030b8751ceab557177a34a6` on `stable`; DESIGNSTATE.md:17 records "3.44.6 / Dart 3.12.2". I did not run `flutter --version` (documentation-only task). The API claims in §5.1 and §4.7 were verified against `api.flutter.dev`, which tracks current stable, not against the pinned revision. **Confirm `SwitchThemeData.trackOutlineColor` / `trackOutlineWidth` and the `ButtonStyle` property list against the installed SDK before implementing.** If the pinned revision predates `trackOutlineColor`, the switch falls back to a custom widget and §4.7 grows by roughly 40 lines.
2. **`ButtonStyle.backgroundBuilder` / `foregroundBuilder` — VERIFIED to exist, deliberately unused.** They appear in the current `ButtonStyle` constructor. Their behaviour across the pinned revision is UNVERIFIED. §5.1 rejects them on design grounds, so this does not block implementation.
3. **Judgement calls, flagged so a reviewer can overrule them:**
   - §4.3 — ghost text buttons get no hard shadow (restraint vs. grammar coverage). The single most likely decision to be wrong.
   - §4.6 — chips move from a full pill to `rControl` (geometry coherence vs. learned shape).
   - §5.4 — focus ring is in-place, not outward-offset (no layout change vs. literal reading of the brief).
   - §4.7 — the switch keeps its stadium track; radius is not controllable.
   - §4.1 — the pressed fill inverts to `ink`/`canvas` rather than tinting toward `accentPressed`, because `accentPressed` fails 4.5:1 (§7.1).
   - §6.8 — the 32dp chip is left below 48dp rather than enlarged, because enlarging reflows three screens.
4. **Not specified, deliberately:** the `filledButtonTheme` / `outlinedButtonTheme` / `textButtonTheme` blocks are left in `app_theme.dart` (dead for the app's own widgets, live for any Material button a dependency introduces). Removing them is a separate decision. The app now mounts **zero** Material buttons of its own (§4.16), which makes them dead code in the strict sense — they are kept anyway, because §5.5 says to keep them and deleting a fallback is not part of a restyle.
5. **Deliberately absent:** no screenshot or visual reference. Every value in this document is a number with a derivation, a constraint, or a labelled judgement call. Where a value could not be derived, §10.3 says so rather than inventing a rationale.

### 10.1 Added by the §2.5 reversal — for a reviewer to check first

1. **THE GAP: a dialog has no hard shadow.** §4.11 item 4. `Material` cannot
   take a `boxShadow`, and the eight `AlertDialog` sites are not wrapped. Shipped
   state: 2pt edge + `rControl` + `elevation: 0`, no shadow. The one-line remedy
   does not exist; the real remedy is a shared wrapper applied to all eight sites,
   which is a new spec.
2. **Three surfaces beyond the literal enumeration were also restyled**, and each
   is called out so a reviewer can object individually rather than discover them:
   the home **error banner** (§4.13 — same class as the two banners beside it),
   Detail's **web-result tile** and the **onboarding mock panel** (both
   `paper`-filled rounded containers with a hairline, i.e. the same class as a
   card), and the home **batch bar** / **Ask bar** (§4.9's contract). Leaving any
   of them soft is the §6.1 incoherence on a screen the reversal was about.
3. **`delete_everything_test.dart:391` fails on this Windows checkout**, for a
   reason that predates and is unrelated to this work: it asserts a 40-character
   source window contains `'catch'`, and the working tree uses CRLF, so the window
   is `\r\n    `. Not fixed here — it is a test bug in a file this phase did not
   need to touch, and fixing it would mean changing a test unrelated to the
   restyle. Named so nobody re-diagnoses it.
4. **The pre-existing 4.37:1 dark-mode error-banner text** (§7.1) was found while
   auditing the reversal, and deliberately left. Fixing it means choosing a
   different palette step, which §9 forbids for a visual restyle. It is a real
   SC 1.4.3 failure and it is not going away by being written down here.
5. **UNVERIFIED, and it is the one claim that could be wrong on device:** that the
   hard edge on a `paper` card at 2pt is not *too* strong next to a `paper` sheet,
   where both now carry `stone` at the same weight. Both edges are on the same
   fill with the same colour, so where a card sits on a sheet the two 2pt lines
   are 8dp apart and read as a double rule. The stacking the app actually
   produces is card-on-canvas and sheet-over-scrim, never card-on-sheet, so this
   is a theoretical collision — but it is the one to look at first on a device,
   and the fix if it is real is a different edge step for one of the two.
6. **Judgement calls made by this phase, flagged so a reviewer can overrule
   them:**
   - §4.12 — labels get the hard edge but **no** shadow. This is the single
     decision that keeps the reversal from making every badge look pressable,
     and it is the one most likely to be reversed back.
   - §4.14 — the assistant essay gets **no** bubble.
   - §4.15 — row separators stay at the hairline even though `dividerTheme` was
     raised. §4.15 states the colour arithmetic for it.
   - §4.10 — the selected card keeps `accent` at 2.97:1 rather than taking a new
     selection colour.
   - §4.11 — `snackBarTheme` takes the slab edge (`edgeOnFill`), not
     `surfaceEdge`, because `ink` in dark mode is a cream fill.
   - §4.16 — the OCR copy button is `outline` at height 36 with the restored 12pt
     `metaLabel`,
     which is a *lot* of pinning for a copy affordance; all of it is there to
     keep the block from growing and the label from turning 1.00:1.
