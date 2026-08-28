# Data Clip

Transforms clipboard tabular data (paste from a spreadsheet, a CSV, a
terminal table) into `R`'s `tibble::tribble`, Python Polars/Pandas
`DataFrame`, SQL `IN`/`VALUES` clauses, or a Markdown table — a keybinding
overlay, not a bar widget.

## Install

```bash
omarchy plugin add https://github.com/Ch3w3y/omarchy-data-clip.git --enable
```

Requires `wl-clipboard` (`wl-paste`), which a default Omarchy install
already has. `transform.py` does the actual parsing/formatting — pure
Python standard library, nothing extra to install.
