#!/usr/bin/env python3
"""
add_go.py — เติมคำสั่ง GO เข้าไปในไฟล์ .sql เพื่อแบ่ง batch

ทำไมต้องมี: ไฟล์ .sql ที่ export มาจาก tool (เช่น pandas/DBeaver export) มักไม่มี
คำสั่ง GO คั่นเลย ทำให้ sqlcmd/DBeaver ส่งทั้งไฟล์เป็น batch เดียว จน connection
หลุด (TCP Provider: Error code 0x68). สคริปต์นี้เติม GO ทุก ๆ N statement ให้อัตโนมัติ

ใช้:  python3 add_go.py <ไฟล์ต้นทาง> <ไฟล์ปลายทาง> [batch_size]
ตัวอย่าง:  python3 add_go.py in.sql out.sql 500
"""
import sys


def add_go(src, dst, batch_size=500):
    n = 0
    with open(src, "r", encoding="utf-8", errors="replace") as fin, \
         open(dst, "w", encoding="utf-8") as fout:
        for line in fin:
            fout.write(line)
            if line.rstrip().endswith(";"):
                n += 1
                if n % batch_size == 0:
                    fout.write("GO\n")
        fout.write("GO\n")
    return n


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("ใช้: python3 add_go.py <src.sql> <dst.sql> [batch_size]")
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2]
    batch = int(sys.argv[3]) if len(sys.argv) > 3 else 500
    count = add_go(src, dst, batch)
    print(f"   Batched OK: {count} statements, GO every {batch}")
