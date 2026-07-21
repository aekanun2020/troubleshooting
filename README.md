# นำเข้าไฟล์ .sql เข้า SQL Server แบบง่าย (Import Toolkit)

ชุดสคริปต์นี้ช่วยให้ผู้เรียน **นำเข้าไฟล์ `.sql` ทั้งหมดเข้า SQL Server ได้ในคำสั่งเดียว**
โดยไม่ต้องเปิดไฟล์ใน DBeaver (ที่ค้าง/ขึ้นนาฬิกาทราย) และไม่ต้องพิมพ์คำสั่งทีละไฟล์เอง

## ปัญหาที่แก้

ไฟล์ `.sql` ที่ export มา **ไม่มีคำสั่ง `GO` คั่น batch เลย** ทำให้:

- **DBeaver** พยายาม parse/render ทั้งไฟล์ → ค้าง (นาฬิกาทราย)
- **sqlcmd** ส่งทั้งไฟล์เป็น batch เดียว → connection หลุด
  (`TCP Provider: Error code 0x68 — Communication link failure`)

สคริปต์นี้จะ **เติม `GO` ให้อัตโนมัติทุก 500 statement** แล้วนำเข้าให้ตามลำดับที่ถูกต้อง
(ตาราง dimension ก่อน → ตาราง fact ทีหลัง)

## ไฟล์ข้อมูลมาให้ใน repo แล้ว

ไม่ต้องดาวน์โหลดเพิ่ม — ไฟล์ `.sql` อยู่ในโฟลเดอร์ `sql/` ให้แล้ว
(ไฟล์ fact ขนาด 156MB ถูกบีบอัดเป็น `.sql.gz` เพื่อให้เก็บใน git ได้ — สคริปต์จะคลายให้เองตอนรัน)

## สิ่งที่ต้องมีก่อน

1. Docker Desktop เปิดอยู่ และ container SQL Server กำลังทำงาน (ค่าเริ่มต้นชื่อ `sql_server`)

> ไม่ต้องติดตั้ง Python บนเครื่อง — สคริปต์จะคลายไฟล์ `.gz` และเติม `GO` ให้ทั้งหมด **ภายใน Docker container** ให้เองโดยอัตโนมัติ

```
import-toolkit/
├── sql/
│   ├── application_type_dim_202602251308.sql   ✅ อยู่ใน repo
│   ├── emp_length_dim_202602251308.sql        ✅ อยู่ใน repo
│   ├── home_ownership_dim_202602251308.sql    ✅ อยู่ใน repo
│   ├── issue_d_dim_202602251308.sql           ✅ อยู่ใน repo
│   ├── loan_status_dim_202602251308.sql       ✅ อยู่ใน repo
│   └── loans_fact_202602251308.sql.gz         ✅ อยู่ใน repo (บีบอัด 21MB)
├── add_go.py         (helper เติม GO)
├── gunzip.py         (helper คลาย .gz — รันภายใน container ให้อัตโนมัติ)
├── import_all.sh     (สำหรับ Mac / Linux)
├── import_all.bat    (สำหรับ Windows)
└── README.md
```

> หมายเหตุ: ไฟล์ `allrawloanstat` (528MB) ไม่ได้รวมอยู่ใน repo ตามที่กำหนด

## ขั้นตอนที่ 1: ดาวน์โหลดไฟล์มาที่เครื่อง (ไม่ต้องใช้ git)

วิธีที่ง่ายที่สุดสำหรับผู้เรียน — ไม่ต้องติดตั้ง git แค่กดปุ่มเดียว

### กดดาวน์โหลด ZIP

คลิกลิงก์นี้เพื่อโหลดไฟล์ทั้งหมดเป็นไฟล์ ZIP ก้อนเดียว (ได้ทั้งสคริปต์และไฟล์ .sql):

**[⬇️ คลิกที่นี่เพื่อดาวน์โหลด ZIP](https://github.com/aekanun2020/troubleshooting/archive/refs/heads/main.zip)**

หรือเข้าหน้า repo → กดปุ่มเขียว **`< > Code`** → เลือก **Download ZIP**

### แตกไฟล์ (unzip)

**บน macOS:**
1. เปิดโฟลเดอร์ **Downloads** → ดับเบิ้ลคลิกที่ไฟล์ `troubleshooting-main.zip` → จะแตกเป็นโฟลเดอร์ `troubleshooting-main` ให้อัตโนมัติ
2. แนะนำ: ย้ายโฟลเดอร์นี้ไปไว้ที่หาง่าย เช่น **Desktop** (หน้าจอ)

**บน Windows:**
1. เปิดโฟลเดอร์ **Downloads** → คลิกขวาที่ไฟล์ `troubleshooting-main.zip` → เลือก **Extract All...** → กด **Extract**
2. แนะนำ: แตกไปไว้ที่หาง่าย เช่น **Desktop**

### เปิด Terminal / Command Prompt มาที่โฟลเดอร์ที่แตกไว้

**บน macOS (วิธีง่ายสุด):**
1. เปิดแอป **Terminal** (กด `Cmd + Space` แล้วพิมพ์ Terminal)
2. พิมพ์ `cd ` (มีเว้นวรรคต่อท้าย) **แล้วลากโฟลเดอร์ `troubleshooting-main` จาก Finder มาวางในหน้าต่าง Terminal** (path จะเติมให้อัตโนมัติ) → กด Enter

```bash
cd /Users/<username>/Desktop/troubleshooting-main
```

**บน Windows (วิธีง่ายสุด):**
1. เปิดโฟลเดอร์ `troubleshooting-main` ใน File Explorer
2. คลิกที่ช่อง address bar ด้านบน (ที่แสดง path) → พิมพ์ `cmd` → กด Enter
   (Command Prompt จะเปิดที่โฟลเดอร์นี้ให้อัตโนมัติ)

> เมื่ออยู่ในโฟลเดอร์ที่ถูกต้องแล้ว ให้ดูขั้นตอนที่ 2 ด้านล่างได้เลย

## ขั้นตอนที่ 2: รันสคริปต์นำเข้า

### บน macOS / Linux

ใน Terminal ที่เปิดค้างไว้ที่โฟลเดอร์ (จากขั้นตอนที่ 1) พิมพ์:

```bash
bash import_all.sh
```

### บน Windows

ใน Command Prompt ที่เปิดค้างไว้ที่โฟลเดอร์ (จากขั้นตอนที่ 1) พิมพ์:

```bat
import_all.bat
```

แค่นี้เสร็จ — สคริปต์จะสร้าง database ให้ (ถ้ายังไม่มี), เติม `GO`, และนำเข้าทุกไฟล์ตามลำดับ

## ปรับค่าได้ (ถ้าเครื่องต่างจากค่าเริ่มต้น)

ค่าตั้งต้นอยู่บนหัวของสคริปต์ แก้ได้โดยตรง หรือส่งผ่าน environment variable:

| ตัวแปร | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `CONTAINER` | `sql_server` | ชื่อ Docker container ของ SQL Server |
| `SA_PASSWORD` | `Passw0rd123456` | รหัสผ่าน SA |
| `DATABASE` | `TestDB` | ชื่อ database ปลายทาง |
| `SQL_DIR` | `./sql` | โฟลเดอร์ที่เก็บไฟล์ .sql |
| `BATCH_SIZE` | `500` | เติม GO ทุกกี่ statement |

ตัวอย่าง (Mac/Linux) เปลี่ยนรหัสผ่านและ database:

```bash
SA_PASSWORD='MyPass123!' DATABASE='LoanDB' bash import_all.sh
```

## คำแนะนำระยะยาว

ถ้า export ไฟล์ `.sql` เองจาก Python/pandas ให้ **แทรก `GO` ทุก ๆ 500–1000 statement ตั้งแต่ตอน export**
จะไม่ต้องมาแก้ทีหลังเลย และเปิดใน DBeaver ก็จะไม่ค้างอีก

---

รายละเอียดเชิงลึกของแต่ละอาการและวิธีแก้ ดูได้ที่
[dbeaver-sqlcmd-large-sql-import.md](./dbeaver-sqlcmd-large-sql-import.md)
