# Discrete Fractal Generator

A small x86-64 assembly program that generates fractals by repeatedly
rewriting a string according to per-character rules (like an L-system).
No libc — just raw Linux syscalls.

## How it works

You give it a starting string (the axiom) and rules for how each character
expands. Expanding `n` times means replacing every character with its rule's
expansion, `n` levels deep, and printing whatever's left at the bottom.

If you actually built that expanded string in memory, it would grow
exponentially with `n` and run out of memory pretty fast. So instead of
building the string, the program walks the rules as a graph with an
iterative DFS and only prints characters once it hits depth `n`. It only
ever keeps the current path in memory, not the whole expansion, and streams
output straight to an 8KB buffer as it goes.

The input buffer and the DFS stack both grow on their own via
`mmap`/`mremap`, so there's no hardcoded size limit besides `n` itself
(max 2^32 - 1).

## Build

```bash
make          # -> ./discrete_fractal
make debug    # debug build with symbols, clean rebuild
make clean
```

Needs `nasm` and `ld`.

## Usage

```bash
./discrete_fractal <n> < input.in
```

`n` is decimal, 0 to 2^32 - 1. Anything else (missing arg, extra args,
garbage, out of range) is an error.

## Input format

```
<axiom>
<symbol><expansion for symbol>
<symbol><expansion for symbol>
...
```

- Line 1 is the axiom (the starting string). Printable ASCII only (33–126),
  and it can be empty (just a blank line).
- Every line after that defines one rule: first character is the symbol,
  the rest of the line is what it expands into.
- A symbol with no rule is terminal — it's just printed as-is.
- A rule can expand to nothing (symbol immediately followed by newline) —
  that symbol disappears.
- Each symbol can only be defined once.
- No spaces or control characters anywhere in the input — every byte other
  than the trailing newlines has to be a symbol (33–126).
- Every line, including the last, ends with a newline.

The final string (after `n` iterations) is printed to stdout, followed by
a newline.

## Exit codes

`0` on success, `1` on any error — wrong number of arguments, invalid `n`,
malformed input, or a failed syscall. Either way, whatever memory got
allocated is freed before exiting.

## Example

Axiom `A`, rules `A → AB` and `B → A`:

```
A
AAB
BA
```

| n | output       |
|---|--------------|
| 0 | `A`          |
| 1 | `AB`         |
| 2 | `ABA`        |
| 3 | `ABAAB`      |
| 4 | `ABAABABA`   |

At each step every `A` becomes `AB` and every `B` becomes `A`, all at once —
that's what "iteration" means here.
