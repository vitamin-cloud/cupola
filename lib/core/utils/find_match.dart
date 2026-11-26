/// The matching a library's own search field does: instant, local, and
/// forgiving of case and accents.
///
/// A word typed is the *start* of a word in the name, never a piece from the
/// middle of one: `el` finds `Elephants Dream` and `Ella Fitzgerald`, `fitz`
/// finds `Ella Fitzgerald`, and `phants` finds neither. Several words must each
/// start some word of the name, in any order (`fitz ella`).
library;

/// What the Latin letters with a mark, or a stroke, or a ligature, read as
/// when typed on a keyboard without them: `Björk` is `bjork`, `Mötley Crüe`
/// is `motley crue`, `Sigur Rós` is `sigur ros`.
const Map<String, String> _plain = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ß': 'ss',
  'ť': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ž': 'z',
  'ż': 'z',
};

/// [text] as it is compared: lower case, with the marks taken off.
String foldForFind(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}

final RegExp _notAWordCharacter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The words of [text] as they are compared, [foldForFind]ed.
List<String> findWords(String text) => [
  for (final word in foldForFind(text).split(_notAWordCharacter))
    if (word.isNotEmpty) word,
];

/// [matchesFindQuery] over words already split, for a list searched on every
/// keystroke: the query is folded once and each name once.
bool matchesFindWords(List<String> wanted, List<String> words) {
  for (final prefix in wanted) {
    if (!words.any((word) => word.startsWith(prefix))) return false;
  }
  return true;
}
