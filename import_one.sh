#!/usr/bin/env bash
# ============================================================================
#  import_one.sh  -  นำเข้าไฟล์ .sql (หรือ .sql.gz) เพียงไฟล์เดียวเข้า SQL Server (Docker)
#  สำหรับ Mac / Linux
#
#  ใช้กับตารางเดี่ยว ๆ ที่ไม่เกี่ยวข้อง (ไม่มี foreign key) กับตารางอื่น
#  ชื่อตารางมาจากคำสั่ง CREATE TABLE ในไฟล์ .sql เอง
#
#  ปัญหาที่แก้: ไฟล์ .sql ที่ export มาไม่มีตัวคั่น batch "GO" ทำให้ sqlcmd
#  ส่งทั้งไฟล์เป็น batch เดียว แล้ว connection หลุด (TCP error 0x68)
#  สคริปต์นี้เติม GO ให้อัตโนมัติ
#
#  วิธีใช้:
#    ./import_one.sh  path/to/yourfile.sql
#    ./import_one.sh  path/to/yourfile.sql.gz
# ============================================================================
set -euo pipefail

# ---------- ตั้งค่า (แก้ให้ตรงกับเครื่องคุณ) --------------------------------
CONTAINER="${CONTAINER:-sql_server}"
SA_PASSWORD="${SA_PASSWORD:-Passw0rd123456}"
DATABASE="${DATABASE:-TestDB}"
BATCH_SIZE="${BATCH_SIZE:-500}"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
# ---------------------------------------------------------------------------

# ---- ตรวจ argument ไฟล์ ----------------------------------------------------
if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "วิธีใช้: ./import_one.sh <path/to/file.sql>"
  echo "   หรือ: ./import_one.sh <path/to/file.sql.gz>"
  exit 1
fi
SRC="$1"
if [ ! -f "$SRC" ]; then
  echo "❌ ไม่พบไฟล์: $SRC"
  exit 1
fi

# เป็นไฟล์บีบอัดไหม (ลงท้าย .gz)
IS_GZ=""
case "$SRC" in
  *.gz) IS_GZ=1 ;;
esac

echo "==============================================="
echo " นำเข้าไฟล์เดียวเข้า SQL Server"
echo "   Container : $CONTAINER"
echo "   Database  : $DATABASE"
echo "   ไฟล์       : $SRC"
echo "   Batch size: ใส่ GO ทุก $BATCH_SIZE statement"
echo "==============================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- ตรวจ helper scripts ---------------------------------------------------
if [ ! -f "$SCRIPT_DIR/add_go.py" ]; then
  echo "❌ ไม่พบ add_go.py ข้างสคริปต์นี้ — กรุณาแตกไฟล์ทั้งโฟลเดอร์"
  exit 1
fi
if [ -n "$IS_GZ" ] && [ ! -f "$SCRIPT_DIR/gunzip.py" ]; then
  echo "❌ ไม่พบ gunzip.py ข้างสคริปต์นี้ — กรุณาแตกไฟล์ทั้งโฟลเดอร์"
  exit 1
fi

# ---- ตรวจการเชื่อมต่อ SQL Server (พิสูจน์ว่า container ทำงานอยู่ด้วย) -------
echo "→ ตรวจสอบการเชื่อมต่อ SQL Server ..."
if ! docker exec "$CONTAINER" "$SQLCMD" -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1; then
  echo "❌ เชื่อมต่อ SQL Server ไม่ได้"
  echo "   - Docker เปิดอยู่ และ container '$CONTAINER' ทำงานอยู่ไหม?"
  echo "   - รหัสผ่าน SA ตรงกับ SA_PASSWORD=$SA_PASSWORD ไหม?"
  exit 1
fi
echo "   เชื่อมต่อได้ ✅"

# ---- ตรวจว่ามี python3 ใน container ---------------------------------------
if ! docker exec "$CONTAINER" python3 --version >/dev/null 2>&1; then
  echo "❌ ไม่พบ python3 ใน container '$CONTAINER'"
  echo "   สคริปต์นี้รัน gunzip.py และ add_go.py ภายใน Docker ไม่ใช่บนเครื่อง"
  exit 1
fi

# ---- สร้าง database ถ้ายังไม่มี -------------------------------------------
echo "→ ตรวจสอบ/สร้าง database '$DATABASE' ..."
docker exec "$CONTAINER" "$SQLCMD" -S localhost -U SA -P "$SA_PASSWORD" -C \
  -Q "IF DB_ID('$DATABASE') IS NULL CREATE DATABASE [$DATABASE];" >/dev/null
echo "   พร้อมใช้งาน ✅"

# ---- คัดลอก helper เข้า container -----------------------------------------
docker cp "$SCRIPT_DIR/add_go.py" "$CONTAINER:/tmp/add_go.py" >/dev/null
if [ -n "$IS_GZ" ]; then
  docker cp "$SCRIPT_DIR/gunzip.py" "$CONTAINER:/tmp/gunzip.py" >/dev/null
fi

# ---- ล้าง temp เก่า --------------------------------------------------------
docker exec "$CONTAINER" sh -c "rm -f /tmp/_in.sql /tmp/_in.sql.gz /tmp/_fixed.sql" >/dev/null 2>&1 || true

# ---- คัดลอกไฟล์เข้า, คลาย (ถ้าจำเป็น) + เติม GO ภายใน container ------------
echo ""
if [ -n "$IS_GZ" ]; then
  echo "→ กำลังนำเข้า (ไฟล์บีบอัด): $SRC"
  docker cp "$SRC" "$CONTAINER:/tmp/_in.sql.gz" >/dev/null
  docker exec "$CONTAINER" python3 /tmp/gunzip.py /tmp/_in.sql.gz
  docker exec "$CONTAINER" python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql "$BATCH_SIZE"
else
  echo "→ กำลังนำเข้า: $SRC"
  docker cp "$SRC" "$CONTAINER:/tmp/_in.sql" >/dev/null
  docker exec "$CONTAINER" python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql "$BATCH_SIZE"
fi

# ---- นำเข้าไฟล์ที่แก้แล้ว ---------------------------------------------------
docker exec "$CONTAINER" "$SQLCMD" -S localhost -U SA -P "$SA_PASSWORD" \
  -d "$DATABASE" -C -b -i /tmp/_fixed.sql

echo ""
echo "==============================================="
echo " เสร็จแล้ว นำเข้าไฟล์สำเร็จ ✅"
echo "==============================================="
