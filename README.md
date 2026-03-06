Lil Script I made

# Scripts

This repository is released under the [MIT License](LICENSE.md)


- `stats.sh` – collect line & comment statistics for various file types.

## stats.sh

Usage:

```sh
# run on current directory
../scripts/stats.sh

# specify another directory or file/glob
../scripts/stats.sh path/to/dir
```

By default the script looks at `.` (the directory where it's invoked), or at the path passed as an argument. It also tries `src/<arg>` if the initial argument doesn't exist.

### Supported languages

- Rust (`.rs`)
- C and related filetypes (`.c`, `.h`, `.hpp`, `.hh`, `.cc`, `.cxx`, etc.)
- C++ (`.cpp`)
- Assembly (`.asm`)
- HTML (`.html`)
- CSS (`.css`)
- Shell scripts (`.sh`)
- Makefiles (`Makefile`)
- Markdown (`.md`)
- JavaScript (`.js`, `.jsx`)
- TypeScript (`.ts`, `.tsx`)

Files under a `target/` directory are ignored.

The output is presented as separate tables per language, followed by a summary table listing the found languages and total line counts.