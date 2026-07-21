#!/usr/bin/env python3
"""
gunzip.py — คลายไฟล์ .gz เป็นไฟล์ปกติ (ใช้ได้ทั้ง Windows/Mac/Linux โดยไม่ต้องมี gzip)

ใช้:  python gunzip.py <file.sql.gz>   ->  จะได้ <file.sql>
"""
import gzip
import shutil
import sys

if len(sys.argv) < 2:
    print("ใช้: python gunzip.py <file.sql.gz>")
    sys.exit(1)

src = sys.argv[1]
dst = src[:-3] if src.endswith(".gz") else src + ".out"
with gzip.open(src, "rb") as f_in, open(dst, "wb") as f_out:
    shutil.copyfileobj(f_in, f_out)
print(f"   Decompressed -> {dst}")
