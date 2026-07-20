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

## สิ่งที่ต้องมีก่อน

1. Docker Desktop เปิดอยู่ และ container SQL Server กำลังทำงาน (ค่าเริ่มต้นชื่อ `sql_server`)
2. ไฟล์ `.sql` ทั้งหมดวางไว้ในโฟลเดอร์ `sql/`

```
import-toolkit/
├── sql/
│   ├── application_type_dim_*.sql
│   ├── emp_length_dim_*.sql
│   ├── home_ownership_dim_*.sql
│   ├── issue_d_dim_*.sql
│   ├── loan_status_dim_*.sql
│   ├── loans_fact_*.sql          (ไฟล์ใหญ่ 156MB)
│   └── allrawloanstat_*.sql      (ไฟล์ใหญ่ 528MB)
├── add_go.py
├── import_all.sh     (สำหรับ Mac / Linux)
├── import_all.bat    (สำหรับ Windows)
└── README.md
```

## วิธีใช้

### บน macOS / Linux

เปิด Terminal มาที่โฟลเดอร์นี้ แล้วรัน:

```bash
bash import_all.sh
```

### บน Windows

เปิด Command Prompt มาที่โฟลเดอร์นี้ แล้วรัน:

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
