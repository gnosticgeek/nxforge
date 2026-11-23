//! Cheat codes for a GBA game: the text of a cheat file in, RAM writes once a frame out.
//!
//! The file is the layout NXForge's Switch cheat files use: a `[Name]` line, then the cheat's code lines, two hex
//! words each. A cheat's switch is the caller's to keep. Two families of raw (decrypted) codes are applied:
//!
//! - CodeBreaker / GameShark SP, `XAAAAAAA VVVV`: 3 = 8-bit write, 8 = 16-bit write, 2 = 16-bit OR, 6 = 16-bit AND,
//!   7 = run the next line only if the 16-bit value there equals VVVV, A = only if it differs, D = only if the
//!   buttons held equal VVVV.
//! - GameShark v1/v2 and Action Replay raw, `XAAAAAAA VVVVVVVV`: 0 = 8-bit write, 1 = 16-bit write, 2 = 32-bit write.
//!
//! Encrypted codes (CodeBreaker's 9-type seed, GameShark and Action Replay v3 as published), master codes that hook
//! the game's code, and ROM patches are shown as unsupported and never applied: the recompiled game has no code to
//! hook and no ROM to patch.

use gba_core::Bus as _;

#[derive(Clone)]
enum Op {
    W8(u32, u8),
    W16(u32, u16),
    W32(u32, u32),
    Or16(u32, u16),
    And16(u32, u16),
    IfEq(u32, u16),
    IfNe(u32, u16),
    IfKeys(u16),
}

#[derive(Clone, Default)]
pub struct Cheat {
    pub name: String,
    pub on: bool,
    /// why it cannot be applied; empty when it can
    pub unsupported: String,
    ops: Vec<Op>,
}

#[derive(Default)]
pub struct Cheats {
    pub list: Vec<Cheat>,
}

fn ram(addr: u32) -> bool {
    matches!(addr >> 24, 2 | 3)
}

impl Cheats {
    pub fn parse(text: &str) -> Cheats {
        let mut list: Vec<Cheat> = Vec::new();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with("//") {
                continue;
            }
            if (line.starts_with('[') && line.ends_with(']')) || (line.starts_with('{') && line.ends_with('}')) {
                let mut c = Cheat { name: line[1..line.len() - 1].trim().to_string(), ..Default::default() };
                if line.starts_with('{') {
                    c.unsupported = "a master code: the recompiled game has no code to hook, and needs none".into();
                }
                list.push(c);
                continue;
            }
            let Some(c) = list.last_mut() else { continue };
            let words: Vec<&str> = line.split_whitespace().collect();
            let joined: String;
            let (a, v) = match words.as_slice() {
                [a, v] => (*a, *v),
                [one] if one.len() == 12 || one.len() == 16 => {
                    joined = one.to_string();
                    (&joined[..8], &joined[8..])
                }
                _ => {
                    if c.unsupported.is_empty() {
                        c.unsupported = format!("not a code line: {line}");
                    }
                    continue;
                }
            };
            let (Ok(aw), Ok(vw)) = (u32::from_str_radix(a, 16), u32::from_str_radix(v, 16)) else {
                if c.unsupported.is_empty() {
                    c.unsupported = format!("not a code line: {line}");
                }
                continue;
            };
            if a.len() != 8 {
                c.unsupported = format!("not a code line: {line}");
                continue;
            }
            let kind = aw >> 28;
            let addr = aw & 0x0FFF_FFFF;
            let op = if v.len() == 4 {
                match kind {
                    3 if ram(addr) => Some(Op::W8(addr, vw as u8)),
                    8 if ram(addr) => Some(Op::W16(addr, vw as u16)),
                    2 if ram(addr) => Some(Op::Or16(addr, vw as u16)),
                    6 if ram(addr) => Some(Op::And16(addr, vw as u16)),
                    7 if ram(addr) => Some(Op::IfEq(addr, vw as u16)),
                    0xA if ram(addr) => Some(Op::IfNe(addr, vw as u16)),
                    0xD => Some(Op::IfKeys(vw as u16)),
                    _ => None,
                }
            } else if v.len() == 8 {
                match kind {
                    0 if ram(addr) => Some(Op::W8(addr, vw as u8)),
                    1 if ram(addr) => Some(Op::W16(addr, vw as u16)),
                    2 if ram(addr) => Some(Op::W32(addr, vw)),
                    _ => None,
                }
            } else {
                None
            };
            match op {
                Some(op) => c.ops.push(op),
                None if c.unsupported.is_empty() => {
                    c.unsupported = "an encrypted code, a master code or a ROM patch: only raw RAM codes can be applied".into()
                }
                None => {}
            }
        }
        for c in &mut list {
            if c.ops.is_empty() && c.unsupported.is_empty() {
                c.unsupported = "no code lines".into();
            }
        }
        Cheats { list }
    }

    pub fn apply(&self, bus: &mut gba_core::MemMap) {
        for c in &self.list {
            if !c.on || !c.unsupported.is_empty() {
                continue;
            }
            let mut skip = false;
            for op in &c.ops {
                if std::mem::take(&mut skip) {
                    continue;
                }
                match *op {
                    Op::W8(a, v) => bus.write8(a, v),
                    Op::W16(a, v) => bus.write16(a, v),
                    Op::W32(a, v) => bus.write32(a, v),
                    Op::Or16(a, v) => {
                        let x = bus.read16(a);
                        bus.write16(a, x | v)
                    }
                    Op::And16(a, v) => {
                        let x = bus.read16(a);
                        bus.write16(a, x & v)
                    }
                    Op::IfEq(a, v) => skip = bus.read16(a) != v,
                    Op::IfNe(a, v) => skip = bus.read16(a) == v,
                    Op::IfKeys(v) => skip = (!bus.keys & 0x3FF) != (v & 0x3FF),
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_raw_codes_and_flags_the_rest() {
        let c = Cheats::parse("[Lives]\n33001234 0009\n[Rupees]\n82002AE8 03E7\n{Master}\n00001234 000A\n[Enc]\n9ABCDEF0 1234\n[GS]\n02001234 000000FF\n");
        assert_eq!(c.list.len(), 5);
        assert!(c.list[0].unsupported.is_empty() && c.list[1].unsupported.is_empty() && c.list[4].unsupported.is_empty());
        assert!(!c.list[2].unsupported.is_empty() && !c.list[3].unsupported.is_empty());
    }
}
