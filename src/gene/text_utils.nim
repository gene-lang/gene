import unicode

proc utf8_char_len*(s: string): int {.inline, gcsafe.} =
  s.runeLen

proc utf8_byte_len*(s: string): int {.inline, gcsafe.} =
  s.len

proc utf8_char_pos_for_byte_offset*(s: string, byte_offset: int): int {.gcsafe.} =
  if byte_offset <= 0:
    return 0

  let bounded = min(byte_offset, s.len)
  var i = 0
  while i < bounded:
    i += s.runeLenAt(i)
    result.inc()

proc utf8_byte_offset_for_char_pos*(s: string, char_pos: int): int {.gcsafe.} =
  if char_pos <= 0:
    return 0

  let bounded = min(char_pos, s.runeLen)
  s.runeOffset(bounded)

proc utf8_char_at*(s: string, pos: int): Rune {.inline, gcsafe.} =
  s.runeAtPos(pos)

proc utf8_char_str_at*(s: string, pos: int): string {.inline, gcsafe.} =
  s.runeStrAtPos(pos)

proc utf8_valid*(s: string): bool {.inline, gcsafe.} =
  validateUtf8(s) < 0

proc utf8_has_nul*(s: string): bool {.inline, gcsafe.} =
  for ch in s:
    if ch == '\0':
      return true
  false
