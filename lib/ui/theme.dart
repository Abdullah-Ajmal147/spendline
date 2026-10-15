import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/entry.dart';

/// Liquid-glass palette: translucent panels over a slow aurora of
/// mint, tangerine and lemon. Every color in the app comes from here.
class Palette {
  const Palette({
    required this.bg,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accentInk,
    required this.glass,
    required this.glassStrong,
    required this.edge,
    required this.sheen,
    required this.lo,
    required this.shadow,
    required this.field,
    required this.blobA,
    required this.blobB,
    required this.blobC,
    required this.spent,
    required this.lent,
    required this.recv,
    required this.spentBg,
    required this.lentBg,
    required this.recvBg,
  });

  final Color bg, ink, ink2, ink3, accent, accentInk;
  final Color glass, glassStrong, edge, sheen, lo, shadow, field;
  final Color blobA, blobB, blobC;
  final Color spent, lent, recv, spentBg, lentBg, recvBg;

  static const light = Palette(
    bg: Color(0xFFE4EEEA),
    ink: Color(0xFF0F2420),
    ink2: Color(0xFF47605A),
    ink3: Color(0xFF7A8F8A),
    accent: Color(0xFF0B7A6C),
    accentInk: Color(0xFFFFFFFF),
    glass: Color(0x70FFFFFF),
    glassStrong: Color(0xB8FFFFFF),
    edge: Color(0xCCFFFFFF),
    sheen: Color(0x80FFFFFF),
    lo: Color(0x120F2420),
    shadow: Color(0x29164038),
    field: Color(0x99FFFFFF),
    blobA: Color(0xFF3CC7B4),
    blobB: Color(0xFFFF9F5A),
    blobC: Color(0xFFF2D54C),
    spent: Color(0xFFB93A27),
    lent: Color(0xFF9A6410),
    recv: Color(0xFF127A52),
    spentBg: Color(0x1CB93A27),
    lentBg: Color(0x29C98A1E),
    recvBg: Color(0x1F127A52),
  );

  static const dark = Palette(
    bg: Color(0xFF08130F),
    ink: Color(0xFFE6F2EE),
    ink2: Color(0xFFA2B7B1),
    ink3: Color(0xFF6D847E),
    accent: Color(0xFF52D8C4),
    accentInk: Color(0xFF04201B),
    glass: Color(0x66162A26),
    glassStrong: Color(0xC71A302C),
    edge: Color(0x21FFFFFF),
    sheen: Color(0x1FFFFFFF),
    lo: Color(0x59000000),
    shadow: Color(0x80000000),
    field: Color(0x12FFFFFF),
    blobA: Color(0xFF17796D),
    blobB: Color(0xFFA4501F),
    blobC: Color(0xFF8C7A1F),
    spent: Color(0xFFFF8E78),
    lent: Color(0xFFF2C063),
    recv: Color(0xFF62D9A2),
    spentBg: Color(0x21FF8E78),
    lentBg: Color(0x24F2C063),
    recvBg: Color(0x2162D9A2),
  );

  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color typeColor(EntryType t) => switch (t) {
        EntryType.expense => spent,
        EntryType.given => lent,
        EntryType.received || EntryType.income => recv,
      };

  Color typeBg(EntryType t) => switch (t) {
        EntryType.expense => spentBg,
        EntryType.given => lentBg,
        EntryType.received || EntryType.income => recvBg,
      };
}

const _tabular = [FontFeature.tabularFigures()];

/// Display face: Bricolage Grotesque, for totals and headings.
TextStyle display(double size, {Color? color, FontWeight weight = FontWeight.w700}) => GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.05,
      letterSpacing: size >= 28 ? -0.03 * size : -0.01 * size,
      fontFeatures: _tabular,
    );

/// Body face: Figtree.
TextStyle body(double size, {Color? color, FontWeight weight = FontWeight.w400, double? height}) =>
    GoogleFonts.figtree(fontSize: size, fontWeight: weight, color: color, height: height ?? 1.35, fontFeatures: _tabular);

/// Small uppercase label.
TextStyle eyebrow(Color color, {double size = 11.5}) =>
    GoogleFonts.figtree(fontSize: size, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.0);

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: p.accent, brightness: b, primary: p.accent, onPrimary: p.accentInk),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    textTheme: GoogleFonts.figtreeTextTheme(base.textTheme).apply(bodyColor: p.ink, displayColor: p.ink),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: body(14, color: p.bg, weight: FontWeight.w600),
      actionTextColor: b == Brightness.dark ? p.accentInk : p.blobA,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.field,
      hintStyle: body(15, color: p.ink3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.edge)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.edge)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.accentInk,
        minimumSize: const Size.fromHeight(50),
        shape: const StadiumBorder(),
        textStyle: body(15, weight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.lo),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
