#!/usr/bin/env bash
# =============================================================================
#  import_all.sh  —  นำเข้าไฟล์ .sql ทั้งหมดเข้า SQL Server (บน Docker) แบบอัตโนมัติ
#  รองรับ macOS / Linux
#
#  ปัญหาที่แก้:  ไฟล์ .sql ที่ export มา "ไม่มี GO" คั่น batch เลย
#               ทำให้ทั้ง DBeaver และ sqlcmd พยายามส่งทั้งไฟล์เป็น batch เดียว
#               จน connection หลุด (TCP Provider: Error code 0x68)
#
#  วิธีใช้:      1) วางไฟล์ .sql ทั้งหมดไว้ในโฟลเดอร์ ./sql/
#               2) เปิด Terminal มาที่โฟลเดอร์นี้
#               3) รัน:   bash import_all.sh
# =============================================================================

set -euo pipefail

# ---------- ตั้งค่า (แก้ได้ตามเครื่องของผู้เรียน) ---------------------------
CONTAINER="${CONTAINER:-sql_server}"          # ชื่อ container ของ SQL Server
SA_PASSWORD="${SA_PASSWORD:-Passw0rd123456}"  # รหัสผ่าน SA
DATABASE="${DATABASE:-TestDB}"                # ชื่อ database ปลายทาง
SQL_DIR="${SQL_DIR:-./sql}"                   # โฟลเดอร์ที่เก็บไฟล์ .sql
BATCH_SIZE="${BATCH_SIZE:-500}"               # ใส่ GO ทุกกี่ statement
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"        # path ของ sqlcmd ใน container
# ---------------------------------------------------------------------------

# ลำดับการนำเข้า: dimension ก่อน แล้วค่อย fact (สำคัญเพราะ fact อ้างอิง dimension)
ORDER=(
  "application_type_dim"
  "emp_length_dim"
  "home_ownership_dim"
  "issue_d_dim"
  "loan_status_dim"
  "loans_fact"
  "allrawloanstat"
)

echo "==============================================="
echo " เริ่มนำเข้าข้อมูลเข้า SQL Server"
echo "   Container : $CONTAINER"
echo "   Database  : $DATABASE"
echo "   Batch size: ใส่ GO ทุก $BATCH_SIZE statement"
echo "==============================================="

# ตรวจว่า container ทำงานอยู่ไหม
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "❌ ไม่พบ container ชื่อ '$CONTAINER' ที่กำลังทำงานอยู่"
  echo "   ตรวจดูด้วย: docker ps"
  exit 1
fi

# ตรวจว่าเชื่อมต่อ SQL Server ได้ไหม
echo "→ ตรวจสอบการเชื่อมต่อ SQL Server ..."
if ! docker exec "$CONTAINER" "$SQLCMD" -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1; then
  echo "❌ เชื่อมต่อ SQL Server ไม่ได้ — ตรวจรหัสผ่าน SA หรือสถานะ container"
  exit 1
fi
echo "   เชื่อมต่อได้ ✅"

# สร้าง database ถ้ายังไม่มี
echo "→ ตรวจสอบ/สร้าง database '$DATABASE' ..."
docker exec "$CONTAINER" "$SQLCMD" -S localhost -U SA -P "$SA_PASSWORD" -C \
  -Q "IF DB_ID('$DATABASE') IS NULL CREATE DATABASE [$DATABASE];" >/dev/null
echo "   พร้อมใช้งาน ✅"

# คัดลอก helper สำหรับเติม GO เข้าไปใน container หนึ่งครั้ง
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker cp "$SCRIPT_DIR/add_go.py" "$CONTAINER:/tmp/add_go.py"

# ฟังก์ชัน: เติม GO ให้ไฟล์ แล้วนำเข้า
import_one() {
  local base="$1"
  local src="$SQL_DIR/$base.sql"

  # หาไฟล์แบบยืดหยุ่น: รองรับทั้ง .sql และ .sql.gz (เผื่อชื่อมี timestamp ต่อท้าย)
  local gz=""
  if [ ! -f "$src" ]; then
    src=$(ls "$SQL_DIR/${base}"*.sql 2>/dev/null | head -1 || true)
  fi
  if [ -z "${src:-}" ] || [ ! -f "$src" ]; then
    gz=$(ls "$SQL_DIR/${base}"*.sql.gz 2>/dev/null | head -1 || true)
  fi
  if [ -z "${src:-}" ] && [ -z "${gz:-}" ]; then
    echo "⚠️  ข้าม '$base' — ไม่พบไฟล์ในโฟลเดอร์ $SQL_DIR"
    return 0
  fi

  # ถ้าเป็นไฟล์ .gz ให้คลายก่อน (ครั้งเดียว)
  if [ -n "${gz:-}" ]; then
    src="${gz%.gz}"
    if [ ! -f "$src" ]; then
      echo "→ กำลังคลายไฟล์: $(basename "$gz")"
      gunzip -k "$gz"
    fi
  fi

  local fname; fname=$(basename "$src")
  echo ""
  echo "→ กำลังนำเข้า: $fname"

  # 1) เติม GO ทุก N statement (เขียนไฟล์ที่แก้แล้วไว้ที่ /tmp ใน container)
  docker exec -i "$CONTAINER" bash -c "cat > /tmp/_in.sql" < "$src"
  docker exec "$CONTAINER" python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql "$BATCH_SIZE"

  # 2) นำเข้าไฟล์ที่แก้แล้ว
  docker exec "$CONTAINER" "$SQLCMD" -S localhost -U SA -P "$SA_PASSWORD" \
    -d "$DATABASE" -C -b -i /tmp/_fixed.sql
  echo "   ✅ นำเข้า $fname สำเร็จ"
}

# วนนำเข้าตามลำดับ
for base in "${ORDER[@]}"; do
  import_one "$base"
done

echo ""
echo "==============================================="
echo " 🎉 นำเข้าข้อมูลทั้งหมดเสร็จสมบูรณ์"
echo "==============================================="
