# คู่มือ Import ไฟล์ SQL ขนาดใหญ่ด้วย `sqlcmd` (ฉบับตรวจสอบแล้ว)

คู่มือนี้ใช้กับ SQL Server dump ที่ประกอบด้วยคำสั่ง `INSERT` จำนวนมาก โดยสมมติว่า:

- แต่ละ `INSERT` จบด้วย `;` ที่ท้ายบรรทัด
- ไม่มี stored procedure, function หรือ string literal หลายบรรทัดที่มี `;` อยู่ท้ายบรรทัดภายในข้อความ
- ผู้ใช้มีสิทธิ์เขียนข้อมูลลงฐานข้อมูลเป้าหมาย

> หากไฟล์เป็น SQL ทั่วไปที่มี `CREATE PROCEDURE`, ตัวแปรข้าม statement หรือโครงสร้างซับซ้อน ห้ามแทรก `GO` ด้วยวิธีนับบรรทัดนี้ เพราะอาจแบ่ง batch ผิดตำแหน่ง

## ทำไมจึงใช้ `sqlcmd`

DBeaver สามารถแยกและรัน statement ตาม delimiter `;` ได้ แต่ไฟล์ขนาดใหญ่มากอาจใช้หน่วยความจำสูงหรือทำให้ UI ตอบสนองช้า ส่วน `sqlcmd` อ่านไฟล์จาก command line และใช้ `GO` เป็น batch terminator จึงเหมาะกับงาน import ลักษณะนี้มากกว่า

การแทรก `GO` ทุก 500 คำสั่งช่วยจำกัดขนาดของแต่ละ batch แต่ไม่ได้รับประกันว่าจะแก้ `Communication link failure` ทุกกรณี เพราะ error ดังกล่าวอาจเกิดจาก network, container, resource limit หรือ SQL Server ด้วย

---

## macOS หรือ Windows ที่ใช้ SQL Server ใน Docker

### 1. ตรวจสอบชื่อ container จาก host

เปิด Terminal หรือ PowerShell บนเครื่อง host:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

ตัวอย่างต่อไปนี้สมมติว่า container ชื่อ `sql_server`

### 2. Copy ไฟล์เข้า container

รันจากเครื่อง host ไม่ใช่จาก shell ภายใน container:

```bash
docker cp /path/to/yourfile.sql sql_server:/tmp/yourfile.sql
```

บน Windows PowerShell ตัวอย่างเช่น:

```powershell
docker cp "C:\path\to\yourfile.sql" sql_server:/tmp/yourfile.sql
```

### 3. เข้า container และตรวจสอบเครื่องมือ

```bash
docker exec -it sql_server bash
```

จากนั้นรันภายใน container:

```bash
ls -lh /tmp/yourfile.sql
command -v python3
test -x /opt/mssql-tools18/bin/sqlcmd && echo "sqlcmd found"
```

หากไม่พบ `sqlcmd` ที่ path ข้างต้น ให้ลองตรวจสอบ image รุ่นเก่า:

```bash
test -x /opt/mssql-tools/bin/sqlcmd && echo "legacy sqlcmd found"
```

### 4. สร้างไฟล์ที่แบ่ง batch ทุก 500 คำสั่ง

รันภายใน container:

```bash
python3 - <<'PY'
source_path = '/tmp/yourfile.sql'
target_path = '/tmp/yourfile_fixed.sql'
batch_size = 500

with open(source_path, 'r', encoding='utf-8-sig', newline='') as source, \
     open(target_path, 'w', encoding='utf-8', newline='\n') as target:
    statements_in_batch = 0
    output_ends_with_newline = True

    for line in source:
        target.write(line)
        output_ends_with_newline = line.endswith(('\n', '\r'))
        stripped = line.rstrip()

        if stripped.upper() == 'GO':
            statements_in_batch = 0
        elif stripped.endswith(';'):
            statements_in_batch += 1
            if statements_in_batch == batch_size:
                if not output_ends_with_newline:
                    target.write('\n')
                target.write('GO\n')
                statements_in_batch = 0
                output_ends_with_newline = True

    if statements_in_batch:
        if not output_ends_with_newline:
            target.write('\n')
        target.write('GO\n')

print(target_path)
PY
```

โค้ดนี้รองรับไฟล์ที่ไม่มี newline ท้ายไฟล์ โดยรับประกันว่า `GO` จะอยู่บนบรรทัดใหม่

### 5. ตรวจสอบผลลัพธ์ก่อน import

```bash
ls -lh /tmp/yourfile_fixed.sql
grep -n -m 5 '^GO$' /tmp/yourfile_fixed.sql
grep -c '^GO$' /tmp/yourfile_fixed.sql
```

ตรวจสอบว่าไม่มี `GO` ติดอยู่ท้าย statement:

```bash
grep -n ';GO$' /tmp/yourfile_fixed.sql
```

คำสั่งสุดท้ายควรไม่แสดงผลลัพธ์ ทั้งนี้ `grep` จะคืน exit code `1` เมื่อไม่พบข้อความ ซึ่งเป็นพฤติกรรมปกติ ไม่ใช่ความเสียหายของไฟล์

### 6. ตรวจสอบการเชื่อมต่อและฐานข้อมูล

คำสั่งต่อไปนี้จะถามรหัสผ่านแบบ interactive เพื่อไม่ให้รหัสผ่านปรากฏใน shell history:

```bash
/opt/mssql-tools18/bin/sqlcmd \
  -S localhost \
  -U SA \
  -d master \
  -Q "SET NOCOUNT ON; SELECT DB_ID(N'TestDB') AS database_id;" \
  -b \
  -C
```

เปลี่ยน `SA` และ `TestDB` ให้ตรงกับ environment หาก `database_id` เป็น `NULL` แสดงว่ายังไม่มีฐานข้อมูลนั้น

> `-C` คือการ trust server certificate ใช้ได้กับ local development หรือ certificate ที่ตรวจสอบไว้แล้ว ไม่ควรใช้เพื่อข้ามการตรวจสอบ certificate โดยไม่พิจารณาความเสี่ยงใน production

### 7. Import ด้วย `sqlcmd`

```bash
/opt/mssql-tools18/bin/sqlcmd \
  -S localhost \
  -U SA \
  -d TestDB \
  -i /tmp/yourfile_fixed.sql \
  -f 65001 \
  -b \
  -V 16 \
  -r 1 \
  -C
```

ความหมายของ options สำคัญ:

- `-i` อ่านคำสั่งจากไฟล์
- `-f 65001` กำหนด input เป็น UTF-8
- `-b` ให้ process คืน exit code ที่ไม่ใช่ศูนย์เมื่อพบ SQL error ตามระดับที่กำหนด
- `-V 16` กำหนด error severity ที่ทำให้ `-b` หยุดงาน
- `-r 1` ส่ง error message ไปยัง standard error
- `-C` trust server certificate; ใช้เฉพาะเมื่อเหมาะสมกับ environment

ตรวจสอบ exit code ทันทีหลังคำสั่งจบ:

```bash
echo $?
```

ค่า `0` หมายถึง `sqlcmd` ไม่พบ error ที่เข้าเงื่อนไข `-b/-V` แต่ไม่ได้ยืนยันเชิงธุรกิจว่าจำนวนหรือเนื้อหาข้อมูลถูกต้องทั้งหมด จึงควรตรวจ row count หรือ checksum เพิ่มเติม

### 8. Copy ไฟล์กลับไปยัง host

ออกจาก container ก่อน:

```bash
exit
```

จากนั้นรันบน macOS host:

```bash
docker cp sql_server:/tmp/yourfile_fixed.sql "$HOME/Desktop/yourfile_fixed.sql"
```

หรือ Windows PowerShell:

```powershell
docker cp sql_server:/tmp/yourfile_fixed.sql "$HOME\Desktop\yourfile_fixed.sql"
```

---

## Windows ที่ติดตั้ง SQL Server โดยตรง

สร้างไฟล์ `fix_sql.py`:

```python
source_path = r'C:\path\to\yourfile.sql'
target_path = r'C:\path\to\yourfile_fixed.sql'
batch_size = 500

with open(source_path, 'r', encoding='utf-8-sig', newline='') as source, \
     open(target_path, 'w', encoding='utf-8', newline='\n') as target:
    statements_in_batch = 0
    output_ends_with_newline = True

    for line in source:
        target.write(line)
        output_ends_with_newline = line.endswith(('\n', '\r'))
        stripped = line.rstrip()

        if stripped.upper() == 'GO':
            statements_in_batch = 0
        elif stripped.endswith(';'):
            statements_in_batch += 1
            if statements_in_batch == batch_size:
                if not output_ends_with_newline:
                    target.write('\n')
                target.write('GO\n')
                statements_in_batch = 0
                output_ends_with_newline = True

    if statements_in_batch:
        if not output_ends_with_newline:
            target.write('\n')
        target.write('GO\n')
```

รัน:

```powershell
python .\fix_sql.py
```

จากนั้น import โดยให้ `sqlcmd` ถามรหัสผ่าน:

```powershell
sqlcmd -S localhost -U SA -d TestDB `
  -i "C:\path\to\yourfile_fixed.sql" `
  -f 65001 -b -V 16 -r 1 -C
```

ตรวจสอบ exit code ใน PowerShell:

```powershell
$LASTEXITCODE
```

หากยังไม่มี `sqlcmd` ให้ติดตั้งตามคู่มือทางการของ Microsoft ปัจจุบันมีทั้ง `sqlcmd` รุ่น Go และรุ่น ODBC ซึ่งอาจมีค่าเริ่มต้นบางอย่างต่างกัน

---

## Checklist ก่อนใช้กับข้อมูลจริง

- สำรองฐานข้อมูลหรือมีวิธีกู้คืนก่อน import
- ยืนยันว่าไฟล์เป็นชุด `INSERT` ตามรูปแบบที่คู่มือนี้รองรับ
- ทดลองกับ database ชั่วคราวหรือข้อมูลจำนวนน้อยก่อน
- ตรวจ encoding ของไฟล์ต้นฉบับ
- ตรวจว่า `GO` อยู่บนบรรทัดของตัวเอง
- ใช้ `-b` และตรวจ exit code
- ตรวจ row count, duplicate key และ constraint หลัง import
- อย่าใส่รหัสผ่านตรง ๆ ใน command line

## เอกสารอ้างอิง

- Microsoft Learn: [sqlcmd utility](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility)
- Microsoft Learn: [Commands in the sqlcmd utility](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-commands)
- Microsoft Learn: [Download and install sqlcmd](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-download-install)
- DBeaver Documentation: [SQL execution](https://dbeaver.com/docs/dbeaver/SQL-Execution/)
