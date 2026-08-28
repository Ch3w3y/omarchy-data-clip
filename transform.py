#!/usr/bin/env python3
"""
transform.py - Data Clip Transformer
Parses tabular clipboard text (TSV, CSV, JSON, delimited) and transforms into R, Python, SQL, and Markdown.
"""

import sys
import os
import json
import csv
import io
import re
import subprocess

def detect_delimiter(sample):
    """Detects delimiter from text snippet."""
    first_few_lines = sample.strip().split('\n')[:5]
    if not first_few_lines:
        return '\t'
    
    # Priority check for Tabs (Excel / Sheets standard)
    if any('\t' in line for line in first_few_lines):
        return '\t'
    if any('|' in line for line in first_few_lines):
        return '|'
    if any(',' in line for line in first_few_lines):
        return ','
    if any(';' in line for line in first_few_lines):
        return ';'
    return None

def infer_type(val_str):
    """Infers if string represents int, float, bool, null, or string."""
    s = val_str.strip()
    if s == "" or s.lower() in ["null", "na", "nan", "none", "nil"]:
        return "null", None
    if s.lower() in ["true", "false"]:
        return "bool", s.lower() == "true"
    # Integer
    if re.match(r'^-?\d+$', s):
        try:
            return "int", int(s)
        except ValueError:
            pass
    # Float
    if re.match(r'^-?\d+\.\d+$', s):
        try:
            return "float", float(s)
        except ValueError:
            pass
    return "str", s

def parse_text_table(text):
    text = text.strip()
    if not text:
        return None, "Empty text"
    
    # Check if text is JSON
    if (text.startswith('[') and text.endswith(']')) or (text.startswith('{') and text.endswith('}')):
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list) and len(parsed) > 0 and isinstance(parsed[0], dict):
                headers = list(parsed[0].keys())
                rows = []
                for item in parsed:
                    rows.append([str(item.get(h, "")) for h in headers])
                return {"headers": headers, "rows": rows, "format": "JSON"}, None
        except Exception:
            pass

    delim = detect_delimiter(text)
    if delim:
        reader = csv.reader(io.StringIO(text), delimiter=delim)
        raw_rows = []
        for r in reader:
            cleaned = [c.strip() for c in r]
            if any(cleaned):
                raw_rows.append(cleaned)
        if not raw_rows:
            return None, "No tabular data found"
        
        # Check if first row looks like header
        header = raw_rows[0]
        data_rows = raw_rows[1:]
        
        # If single row or if first row contains only string names while subsequent rows contain numbers
        has_headers = True
        if len(raw_rows) > 1:
            first_types = [infer_type(c)[0] for c in header]
            second_types = [infer_type(c)[0] for c in raw_rows[1]]
            if any(t in ['int', 'float'] for t in first_types) and first_types == second_types:
                # First row might just be data
                has_headers = False
        else:
            has_headers = False
            
        if not has_headers:
            max_cols = max(len(r) for r in raw_rows)
            header = [f"col_{i+1}" for i in range(max_cols)]
            data_rows = raw_rows
            
        # Normalize rows
        num_cols = len(header)
        normalized_rows = []
        for r in data_rows:
            r_norm = r + [""] * (num_cols - len(r))
            normalized_rows.append(r_norm[:num_cols])
            
        fmt_name = "TSV (Excel/Sheets)" if delim == '\t' else ("CSV" if delim == ',' else f"Delimited ('{delim}')")
        return {"headers": header, "rows": normalized_rows, "format": fmt_name}, None
    else:
        # Fallback: single column list
        lines = [line.strip() for line in text.split('\n') if line.strip()]
        if lines:
            return {"headers": ["value"], "rows": [[l] for l in lines], "format": "List / Single Column"}, None
        return None, "Unable to parse text"

# --- GENERATORS ---

def gen_r_tribble(headers, rows):
    col_defs = ", ".join([f"~{h}" for h in headers])
    lines = [f"tibble::tribble(\n  {col_defs},"]
    
    for r_idx, r in enumerate(rows):
        row_vals = []
        for c in r:
            t, v = infer_type(c)
            if t == "null":
                row_vals.append("NA")
            elif t == "bool":
                row_vals.append("TRUE" if v else "FALSE")
            elif t in ["int", "float"]:
                row_vals.append(str(v))
            else:
                escaped = str(c).replace('"', '\\"')
                row_vals.append(f'"{escaped}"')
        comma = "," if r_idx < len(rows) - 1 else ""
        lines.append(f"  {', '.join(row_vals)}{comma}")
    lines.append(")")
    return "\n".join(lines)

def gen_r_dataframe(headers, rows):
    cols_dict = {h: [] for h in headers}
    for r in rows:
        for idx, h in enumerate(headers):
            c = r[idx]
            t, v = infer_type(c)
            if t == "null":
                cols_dict[h].append("NA")
            elif t == "bool":
                cols_dict[h].append("TRUE" if v else "FALSE")
            elif t in ["int", "float"]:
                cols_dict[h].append(str(v))
            else:
                escaped = str(c).replace('"', '\\"')
                cols_dict[h].append(f'"{escaped}"')
                
    args = []
    for h, vals in cols_dict.items():
        args.append(f"  {h} = c({', '.join(vals)})")
    return "data.frame(\n" + ",\n".join(args) + "\n)"

def gen_python_polars(headers, rows):
    cols_dict = {h: [] for h in headers}
    for r in rows:
        for idx, h in enumerate(headers):
            c = r[idx]
            t, v = infer_type(c)
            if t == "null":
                cols_dict[h].append("None")
            elif t == "bool":
                cols_dict[h].append("True" if v else "False")
            elif t in ["int", "float"]:
                cols_dict[h].append(str(v))
            else:
                escaped = str(c).replace('"', '\\"')
                cols_dict[h].append(f'"{escaped}"')
                
    lines = ["import polars as pl\n", "df = pl.DataFrame({"]
    for h, vals in cols_dict.items():
        lines.append(f'    "{h}": [{", ".join(vals)}],')
    lines.append("})")
    return "\n".join(lines)

def gen_python_pandas(headers, rows):
    cols_dict = {h: [] for h in headers}
    for r in rows:
        for idx, h in enumerate(headers):
            c = r[idx]
            t, v = infer_type(c)
            if t == "null":
                cols_dict[h].append("None")
            elif t == "bool":
                cols_dict[h].append("True" if v else "False")
            elif t in ["int", "float"]:
                cols_dict[h].append(str(v))
            else:
                escaped = str(c).replace('"', '\\"')
                cols_dict[h].append(f'"{escaped}"')
                
    lines = ["import pandas as pd\n", "df = pd.DataFrame({"]
    for h, vals in cols_dict.items():
        lines.append(f'    "{h}": [{", ".join(vals)}],')
    lines.append("})")
    return "\n".join(lines)

def gen_sql_in_or_values(headers, rows):
    if len(headers) == 1:
        # Single column -> SQL IN clause
        items = []
        for r in rows:
            c = r[0]
            t, v = infer_type(c)
            if t in ["int", "float"]:
                items.append(str(v))
            elif t == "null":
                items.append("NULL")
            else:
                escaped = str(c).replace("'", "''")
                items.append(f"'{escaped}'")
        return f"IN ({', '.join(items)})"
    else:
        # Multi-column -> SQL VALUES clause
        val_rows = []
        for r in rows:
            items = []
            for c in r:
                t, v = infer_type(c)
                if t in ["int", "float"]:
                    items.append(str(v))
                elif t == "null":
                    items.append("NULL")
                else:
                    escaped = str(c).replace("'", "''")
                    items.append(f"'{escaped}'")
            val_rows.append(f"  ({', '.join(items)})")
        return "VALUES\n" + ",\n".join(val_rows)

def gen_markdown_table(headers, rows):
    header_line = "| " + " | ".join(headers) + " |"
    sep_line = "| " + " | ".join(["---"] * len(headers)) + " |"
    data_lines = []
    for r in rows:
        data_lines.append("| " + " | ".join(r) + " |")
    return "\n".join([header_line, sep_line] + data_lines)

def transform_clipboard(text=None):
    if not text:
        # Read from wl-paste
        try:
            res = subprocess.run(["wl-paste"], capture_output=True, text=True, timeout=2)
            if res.returncode == 0:
                text = res.stdout
        except Exception:
            text = ""
            
    if not text or not text.strip():
        return {"error": "Clipboard is empty or contains no text"}
    
    parsed, err = parse_text_table(text)
    if err or not parsed:
        return {"error": err or "Failed to parse tabular data from clipboard"}
    
    headers = parsed["headers"]
    rows = parsed["rows"]
    
    results = {
        "format": parsed["format"],
        "rowCount": len(rows),
        "colCount": len(headers),
        "headers": headers,
        "sampleRows": rows[:10],
        "options": [
          {
            "id": "tribble",
            "name": "R tibble::tribble",
            "lang": "r",
            "key": "1",
            "code": gen_r_tribble(headers, rows)
          },
          {
            "id": "r_df",
            "name": "R data.frame",
            "lang": "r",
            "key": "2",
            "code": gen_r_dataframe(headers, rows)
          },
          {
            "id": "polars",
            "name": "Python Polars",
            "lang": "python",
            "key": "3",
            "code": gen_python_polars(headers, rows)
          },
          {
            "id": "pandas",
            "name": "Python Pandas",
            "lang": "python",
            "key": "4",
            "code": gen_python_pandas(headers, rows)
          },
          {
            "id": "sql",
            "name": "SQL (IN / VALUES)",
            "lang": "sql",
            "key": "5",
            "code": gen_sql_in_or_values(headers, rows)
          },
          {
            "id": "markdown",
            "name": "Markdown Table",
            "lang": "markdown",
            "key": "6",
            "code": gen_markdown_table(headers, rows)
          }
        ]
    }
    return results

def main():
    raw_input = None
    if len(sys.argv) > 1 and sys.argv[1] == "--text":
        raw_input = sys.argv[2] if len(sys.argv) > 2 else ""
    elif not sys.stdin.isatty():
        raw_input = sys.stdin.read()
        
    res = transform_clipboard(raw_input)
    print(json.dumps(res, indent=2))

if __name__ == "__main__":
    main()
