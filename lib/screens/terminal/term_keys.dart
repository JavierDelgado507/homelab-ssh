import 'package:flutter/material.dart';

// ── Secuencias de escape ─────────────────────────────────────────────────────
const kKeyEsc    = '\x1b';
const kKeyTab    = '\t';
const kKeyEnter  = '\r';
const kKeyBs     = '\x7f';
const kKeyDel    = '\x1b[3~';
const kKeyIns    = '\x1b[2~';
const kKeyUp     = '\x1b[A';
const kKeyDown   = '\x1b[B';
const kKeyRight  = '\x1b[C';
const kKeyLeft   = '\x1b[D';
const kKeyPgUp   = '\x1b[5~';
const kKeyPgDown = '\x1b[6~';
const kKeyHome   = '\x1b[H';
const kKeyEnd    = '\x1b[F';
const kKeyShTab  = '\x1b[Z';
const kKeyF1  = '\x1bOP';  const kKeyF2  = '\x1bOQ';
const kKeyF3  = '\x1bOR';  const kKeyF4  = '\x1bOS';
const kKeyF5  = '\x1b[15~'; const kKeyF6 = '\x1b[17~';
const kKeyF7  = '\x1b[18~'; const kKeyF8 = '\x1b[19~';
const kKeyF9  = '\x1b[20~'; const kKeyF10= '\x1b[21~';
const kKeyF11 = '\x1b[23~'; const kKeyF12= '\x1b[24~';
// Teclas Fn en popup (F13-F20 eliminadas)


class TermKey {
  final String label;
  final String seq;
  final IconData? icon;
  const TermKey(this.label, this.seq, {this.icon});
}

const kRowNav = [
  TermKey('ESC', kKeyEsc),  TermKey('TAB', kKeyTab),  TermKey('⇤', kKeyShTab),
  TermKey('', kKeyUp,    icon: Icons.keyboard_arrow_up),
  TermKey('', kKeyDown,  icon: Icons.keyboard_arrow_down),
  TermKey('', kKeyLeft,  icon: Icons.keyboard_arrow_left),
  TermKey('', kKeyRight, icon: Icons.keyboard_arrow_right),
  TermKey('Home', kKeyHome), TermKey('End', kKeyEnd),
  TermKey('PgUp', kKeyPgUp), TermKey('PgDn', kKeyPgDown),
  TermKey('Ins', kKeyIns),   TermKey('Del', kKeyDel),
  TermKey('↵', kKeyEnter),   TermKey('⌫', kKeyBs),
];

const kRowSym = [
  TermKey('|','|'), TermKey('~','~'), TermKey('/','/' ), TermKey(':',':'),
  TermKey('-','-'), TermKey('_','_'), TermKey('&','&'), TermKey('+','+'),
  TermKey('=','='), TermKey(';',';'),
  TermKey(r'$',r'$'), TermKey('%','%'), TermKey('@','@'), TermKey('#','#'),
  TermKey('!','!'), TermKey('`','`'), TermKey('.','.'), TermKey('*','*'),
  TermKey('^','^'), TermKey('<','<'), TermKey('>','>'),
  TermKey('(','('), TermKey(')',')'), TermKey('{','{'), TermKey('}','}'),
  TermKey('[','['), TermKey(']',']'), TermKey("'","'"),
  TermKey('"','"'), TermKey('\\','\\'), TermKey('?','?'),
];

const kRowCtrl = [
  TermKey('^A','\x01'), TermKey('^B','\x02'), TermKey('^C','\x03'),
  TermKey('^D','\x04'), TermKey('^E','\x05'), TermKey('^F','\x06'),
  TermKey('^G','\x07'), TermKey('^H','\x08'), TermKey('^I','\x09'),
  TermKey('^J','\x0a'), TermKey('^K','\x0b'), TermKey('^L','\x0c'),
  TermKey('^M','\x0d'), TermKey('^N','\x0e'), TermKey('^O','\x0f'),
  TermKey('^P','\x10'), TermKey('^Q','\x11'), TermKey('^R','\x12'),
  TermKey('^S','\x13'), TermKey('^T','\x14'), TermKey('^U','\x15'),
  TermKey('^V','\x16'), TermKey('^W','\x17'), TermKey('^X','\x18'),
  TermKey('^Y','\x19'), TermKey('^Z','\x1a'),
];

const kRowFn = [
  TermKey('F1',kKeyF1),  TermKey('F2',kKeyF2),  TermKey('F3',kKeyF3),  TermKey('F4',kKeyF4),
  TermKey('F5',kKeyF5),  TermKey('F6',kKeyF6),  TermKey('F7',kKeyF7),  TermKey('F8',kKeyF8),
  TermKey('F9',kKeyF9),  TermKey('F10',kKeyF10), TermKey('F11',kKeyF11), TermKey('F12',kKeyF12),
];
