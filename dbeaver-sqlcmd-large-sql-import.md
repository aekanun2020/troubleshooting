# คู่มือแก้ปัญหา DBeaver/sqlcmd Hang เมื่อ Import ไฟล์ .sql ขนาดใหญ่

## สาเหตุของปัญหา

ไฟล์ .sql ที่มีขนาดใหญ่ (หลายสิบ-หลายร้อย MB) ที่ export ออกมาเป็นชุด `INSERT INTO ... VALUES (...);` ต่อเนื่องกันโดยไม่มีคำสั่ง `GO` แบ่ง batch เลย จะทำให้ทั้ง DBeaver และ `sqlcmd` พยายามส่งคำสั่งทั้งหมดเป็น **1 batch เดียว** ไปให้ SQL Server ประมวลผล ทำให้เกิดอาการค้าง (นาฬิกาทรายใน DBeaver) หรือ connection หลุดกลางทาง (`TCP Provider: Error code 0x68 - Communication link failure` เวลาใช้ sqlcmd)

## วิธีแก้ที่ได้ผลจริง

เติมคำสั่ง `GO` แทรกเข้าไปทุกๆ 500 statements ในไฟล์ เพื่อบอกให้ sqlcmd/SQL Server แบ่งการประมวลผลเป็นก้อนเล็กๆ ต่อเนื่องกัน แทนที่จะส่งทีเดียวทั้งไฟล์

---

## คู่มือสำหรับ macOS (ใช้ Docker container)

### ขั้นตอนที่ 1: เข้า container ที่รัน SQL Server

เปิด Terminal บน Mac แล้วรัน:

```bash
docker exec -it sql_server bash
```

> เปลี่ยน `sql_server` เป็นชื่อ container จริงของคุณ (ดูได้จาก `docker ps`)

### ขั้นตอนที่ 2: ตรวจสอบว่าไฟล์ .sql อยู่ใน container แล้ว

```bash
ls -l /*.sql
```

ถ้ายังไม่มี ให้ copy จาก Mac เข้า container ก่อน (รันจาก Terminal ปกติ ไม่ใช่ใน container):

```bash
docker cp /path/to/yourfile.sql sql_server:/yourfile.sql
```

### ขั้นตอนที่ 3: สร้างไฟล์ใหม่ที่เติม GO แบ่ง batch

ภายใน container (bash prompt ของ container):

```bash
python3 -c "
with open('/yourfile.sql') as f, open('/tmp/yourfile_fixed.sql', 'w') as out:
    count = 0
    for line in f:
        out.write(line)
        if line.rstrip().endswith(';'):
            count += 1
            if count % 500 == 0:
                out.write('GO\n')
    out.write('GO\n')
"
```

> **สำคัญ**: เขียนไฟล์ผลลัพธ์ไปที่ `/tmp/` เพราะ root directory `/` มักไม่มี permission ให้ user เขียนไฟล์ได้

### ขั้นตอนที่ 4: ตรวจสอบไฟล์ที่สร้างใหม่

```bash
ls -l /tmp/yourfile_fixed.sql
grep -c "^GO$" /tmp/yourfile_fixed.sql
```

ควรเห็นตัวเลขมากกว่า 0 (จำนวน GO ที่แทรกเข้าไป)

### ขั้นตอนที่ 5: รันไฟล์ที่แก้แล้วด้วย sqlcmd

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P Passw0rd123456 -d TestDB -i /tmp/yourfile_fixed.sql -C
```

> เปลี่ยน `SA`, `Passw0rd123456`, `TestDB` ให้ตรงกับ username/password/database ของคุณ

### ขั้นตอนที่ 6 (ทางเลือก): ถ้าไม่อยากรันซ้ำทุกครั้งใน container

Copy ไฟล์ fixed ออกมาที่ Mac เพื่อเก็บไว้ใช้ครั้งหน้า:

```bash
docker cp sql_server:/tmp/yourfile_fixed.sql ~/Desktop/yourfile_fixed.sql
```

---

## คู่มือสำหรับ Windows

### กรณีที่ 1: ใช้ Docker Desktop บน Windows

ขั้นตอนเหมือน macOS ทุกอย่าง เพียงเปิด Terminal ผ่าน **PowerShell** หรือ **Command Prompt** แทน:

```powershell
docker exec -it sql_server bash
```

จากนั้นทำตามขั้นตอนที่ 2-6 แบบเดียวกับ macOS ด้านบน (คำสั่งภายใน container เหมือนกันทุกประการ เพราะเป็น Linux container)

### กรณีที่ 2: ใช้ SQL Server ติดตั้งตรงบน Windows (ไม่ผ่าน Docker)

#### ขั้นตอนที่ 1: เตรียมไฟล์ Python script

สร้างไฟล์ชื่อ `fix_sql.py` ด้วย Notepad หรือ text editor:

```python
with open(r'C:\path\to\yourfile.sql', encoding='utf-8') as f, \
     open(r'C:\path\to\yourfile_fixed.sql', 'w', encoding='utf-8') as out:
    count = 0
    for line in f:
        out.write(line)
        if line.rstrip().endswith(';'):
            count += 1
            if count % 500 == 0:
                out.write('GO\n')
    out.write('GO\n')
```

> แก้ path ให้ตรงกับตำแหน่งไฟล์จริงของคุณ

#### ขั้นตอนที่ 2: รัน script (ต้องมี Python ติดตั้งไว้)

เปิด Command Prompt หรือ PowerShell:

```powershell
python fix_sql.py
```

#### ขั้นตอนที่ 3: รันไฟล์ที่แก้แล้วด้วย sqlcmd

```powershell
sqlcmd -S localhost -U SA -P Passw0rd123456 -d TestDB -i "C:\path\to\yourfile_fixed.sql"
```

> ถ้ายังไม่มี `sqlcmd` ให้ดาวน์โหลดจาก Microsoft: ค้นหา "sqlcmd utility download Windows" หรือติดตั้งผ่าน SQL Server Management Studio (SSMS) ซึ่งมี sqlcmd ติดตั้งมาด้วยอยู่แล้ว

---

## สรุปสิ่งที่ต้องจำ

| ปัญหา | วิธีแก้ |
|---|---|
| DBeaver ขึ้นนาฬิกาทรายตอนเปิดไฟล์ใหญ่ | ไม่เปิดไฟล์เข้า SQL Editor เลย ใช้ sqlcmd/bcp แทน |
| sqlcmd หลุด `Communication link failure` (0x68) | เติม `GO` แบ่ง batch ทุก 500 statements |
| Permission denied เวลาเขียนไฟล์ผลลัพธ์ | เขียนไปที่ `/tmp/` (Linux/container) แทน root `/` |
| ต้องการป้องกันปัญหานี้ในอนาคต | ตั้งค่า export script (Python/pandas) ให้แทรก `GO` อัตโนมัติทุก 500 statements ตั้งแต่ตอน generate ไฟล์ .sql |

## คำแนะนำระยะยาว

ถ้าไฟล์ .sql เหล่านี้ถูก generate มาจาก Python/pandas script เป็นประจำ ควรแก้ script ต้นทางให้แทรก `GO` อัตโนมัติทุกๆ 500 statements ตั้งแต่ตอนสร้างไฟล์ จะไม่ต้องมาแก้ไฟล์ทีหลังทุกครั้ง และช่วยให้ import ผ่าน DBeaver หรือ sqlcmd ได้ราบรื่นตั้งแต่ครั้งแรก
