#!/usr/bin/env python3
"""Independent raw-instruction checker for TMH full-core scenario 4.

This script consumes CVA6's retired-instruction trace (``trace_hart_0.dasm``),
not TMH RTL signals or counter values.  It implements the phase-1 five-class
policy needed by scenario 4, applies TMH control writes, and checks that every
one of the 25 clear/two-class/snapshot/read transactions yields one selected
pair.

It intentionally has no HDL dependency.  Its decoder is deliberately small:
it covers the instructions emitted by scenario 4 and maps every other
instruction to X, the uncounted history separator.
"""

from __future__ import annotations

import argparse
import re
from collections import Counter
from pathlib import Path


CLASSES = "BLSAN"
TRACE_WORD = re.compile(r"DASM\(([0-9a-fA-F]{8})\)")


def instruction_class(word: int) -> str | None:
    """Return B/L/S/A/N, or None for X, from an architectural instruction."""
    if word & 0b11 != 0b11:
        # Scenario 4 contains c.addi x5, 1 only; it is arithmetic.
        return "A" if word & 0xFFFF == 0x0285 else None

    opcode = word & 0x7F
    funct3 = (word >> 12) & 0x7
    if opcode in (0x63, 0x6F, 0x67):
        return "B"
    if opcode == 0x03:
        return "L"
    if opcode == 0x23:
        return "S"
    if opcode == 0x13:
        return "N" if funct3 in (0x4, 0x6, 0x7) else "A"
    if opcode in (0x17, 0x37):
        return "A"
    return None


def csr_fields(word: int) -> tuple[int, int, int] | None:
    """Return CSR address, funct3, zimm for immediate CSR instructions."""
    if word & 0x7F != 0x73:
        return None
    funct3 = (word >> 12) & 0x7
    if funct3 not in (0x5, 0x6, 0x7):
        return None
    return ((word >> 20) & 0xFFF, funct3, (word >> 15) & 0x1F)


def csr_read_address(word: int) -> int | None:
    """Return the address for a register-form CSR read with rs1=x0."""
    if word & 0x7F != 0x73:
        return None
    if ((word >> 12) & 0x7) != 0x2 or ((word >> 15) & 0x1F) != 0:
        return None
    return (word >> 20) & 0xFFF


def retired_words(path: Path) -> list[int]:
    words: list[int] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = TRACE_WORD.search(line)
        if match:
            words.append(int(match.group(1), 16))
    if not words:
        raise ValueError(f"no DASM words found in {path}")
    return words


def check(words: list[int]) -> None:
    enabled = False
    previous: str | None = None
    selected = 0
    live: Counter[int] = Counter()
    shadow: Counter[int] = Counter()
    observed: set[int] = set()
    snapshot_reads = 0

    for word in words:
        current = instruction_class(word)
        if enabled and previous is not None and current is not None:
            live[CLASSES.index(previous) * 5 + CLASSES.index(current)] += 1
        previous = current  # None is X and deliberately breaks history.

        # Register-form CSR reads are deliberately separate from immediate
        # CSR writes. Scenario 4 uses csrr TMH_CNT_LO,rd.
        read_address = csr_read_address(word)
        if read_address == 0x7C5:
            snapshot_reads += 1
            if shadow[selected] != 1:
                raise AssertionError(
                    f"TMH_CNT_LO read for pair {selected} expected 1, got {shadow[selected]}"
                )
            observed.add(selected)

        fields = csr_fields(word)
        if fields is None:
            continue
        address, funct3, zimm = fields
        if address == 0x7C3:
            prior = int(enabled)
            value = zimm if funct3 == 0x5 else (zimm | prior if funct3 == 0x6 else prior & ~zimm)
            if value & 0x4:
                live.clear()
                previous = None
            if value & 0x2:
                shadow = live.copy()
            enabled = bool(value & 0x1)
        elif address == 0x7C4:
            selected = min(zimm, 24)

    if observed != set(range(25)):
        missing = sorted(set(range(25)) - observed)
        raise AssertionError(f"did not observe all 25 selected pairs; missing {missing}")
    if snapshot_reads != 25:
        raise AssertionError(f"expected 25 scenario-4 low-counter reads, got {snapshot_reads}")
    print(f"PASS: {snapshot_reads} independent snapshot checks; all 25 B/L/S/A/N pairs equal 1")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="CVA6 trace_hart_0.dasm from scenario 4")
    args = parser.parse_args()
    check(retired_words(args.trace))


if __name__ == "__main__":
    main()
