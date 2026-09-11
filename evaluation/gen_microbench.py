#!/usr/bin/env python3
"""Generate small RV32IMC C/assembly kernels for HAMSA characterization.

The generated sources are intentionally tiny and deterministic. They are not a
replacement for CoreMark/Embench; they explain why IPC changes by exercising
specific issue rules.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent / "microbench"
OUT.mkdir(parents=True, exist_ok=True)

COMMON = r'''
#include <stdint.h>
volatile uint32_t sink;
static inline void finish(uint32_t x) { sink = x; }
'''

BENCHES = {
"independent_alu.c": COMMON + r'''
int main(void) {
  register uint32_t a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8;
  for (uint32_t i=0;i<4096;i++) {
    asm volatile(
      "add %0,%0,%4\n\t"
      "xor %1,%1,%5\n\t"
      "or  %2,%2,%6\n\t"
      "sub %3,%3,%7\n\t"
      : "+r"(a), "+r"(b), "+r"(c), "+r"(d)
      : "r"(e), "r"(f), "r"(g), "r"(h));
  }
  finish(a^b^c^d); return 0;
}
''',
"raw_chain.c": COMMON + r'''
int main(void) {
  register uint32_t a=1,b=3;
  for (uint32_t i=0;i<4096;i++) {
    asm volatile(
      "add %0,%0,%1\n\t"
      "xor %0,%0,%1\n\t"
      "add %0,%0,%1\n\t"
      "sub %0,%0,%1\n\t"
      : "+r"(a) : "r"(b));
  }
  finish(a); return 0;
}
''',
"mul_alu.c": COMMON + r'''
int main(void) {
  register uint32_t a=3,b=5,c=7,d=11;
  for (uint32_t i=0;i<2048;i++) {
    asm volatile(
      "mul %0,%0,%2\n\t"
      "add %1,%1,%3\n\t"
      : "+r"(a), "+r"(b) : "r"(c), "r"(d));
  }
  finish(a^b); return 0;
}
''',
"load_alu.c": COMMON + r'''
static volatile uint32_t data[64];
int main(void) {
  uint32_t s=0,x=1;
  for (uint32_t i=0;i<64;i++) data[i]=i+1;
  for (uint32_t r=0;r<128;r++) {
    for (uint32_t i=0;i<64;i++) {
      s += data[i];
      x = (x << 1) ^ 0x13579bdfu;
    }
  }
  finish(s^x); return 0;
}
''',
"branch_mix.c": COMMON + r'''
int main(void) {
  uint32_t a=1,b=0;
  for (uint32_t i=0;i<8192;i++) {
    if ((i & 7u) == 0) a += 3; else a ^= i;
    b += 0x10203u;
  }
  finish(a^b); return 0;
}
''',
}

for name, text in BENCHES.items():
    (OUT / name).write_text(text)
print(f"generated {len(BENCHES)} microbenchmarks in {OUT}")
