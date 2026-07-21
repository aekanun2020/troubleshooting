@echo off
REM ============================================================================
REM  import_all.bat  -  Auto-import all .sql files into SQL Server (Docker)
REM  For Windows
REM
REM  Problem it fixes: exported .sql files have NO "GO" batch separators, so both
REM  DBeaver and sqlcmd try to send the whole file as one batch and the
REM  connection drops (TCP Provider: Error code 0x68).
REM
REM  How to use:
REM    1) Put all .sql files in the .\sql\ folder
REM    2) Open Command Prompt in this folder (or just double-click this file)
REM    3) Run:   import_all.bat
REM ============================================================================
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ---------- Settings (edit to match your machine) --------------------------
if "%CONTAINER%"==""    set "CONTAINER=sql_server"
if "%SA_PASSWORD%"==""  set "SA_PASSWORD=Passw0rd123456"
if "%DATABASE%"==""     set "DATABASE=TestDB"
if "%SQL_DIR%"==""      set "SQL_DIR=%~dp0sql"
if "%BATCH_SIZE%"==""   set "BATCH_SIZE=500"
set "SQLCMD=/opt/mssql-tools18/bin/sqlcmd"
REM ---------------------------------------------------------------------------

echo ===============================================
echo  Importing data into SQL Server
echo    Container : %CONTAINER%
echo    Database  : %DATABASE%
echo    SQL folder: %SQL_DIR%
echo    Batch size: insert GO every %BATCH_SIZE% statements
echo ===============================================

REM Import order: dimensions first, then facts
set ORDER=application_type_dim emp_length_dim home_ownership_dim issue_d_dim loan_status_dim loans_fact allrawloanstat

REM ---- Check helper scripts exist next to this .bat -------------------------
if not exist "%~dp0add_go.py" (
  echo [ERROR] add_go.py not found next to this script. Please extract the whole folder.
  exit /b 1
)
if not exist "%~dp0gunzip.py" (
  echo [ERROR] gunzip.py not found next to this script. Please extract the whole folder.
  exit /b 1
)

REM ---- Check SQL Server connection (also proves the container is running) ----
echo -^> Checking SQL Server connection ...
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -C -Q "SELECT 1" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Cannot connect to SQL Server.
  echo         - Is Docker Desktop running and the "%CONTAINER%" container started?
  echo         - Does the SA password match SA_PASSWORD=%SA_PASSWORD% ?
  exit /b 1
)
echo    Connected OK

REM ---- Check python3 exists inside the container (decompression runs there) --
echo -^> Checking Python inside the container ...
docker exec %CONTAINER% python3 --version >nul 2>&1
if errorlevel 1 (
  echo [ERROR] python3 is not available inside container "%CONTAINER%".
  echo         This importer runs gunzip.py and add_go.py inside Docker, not on Windows.
  exit /b 1
)
echo    Python OK

REM ---- Create database if missing -------------------------------------------
echo -^> Ensuring database "%DATABASE%" exists ...
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -C -Q "IF DB_ID('%DATABASE%') IS NULL CREATE DATABASE [%DATABASE%];" >nul
if errorlevel 1 (
  echo [ERROR] Could not create or verify database "%DATABASE%".
  exit /b 1
)
echo    Ready

REM ---- Copy helpers into the container once (decompress + GO-batching run
REM      INSIDE the container, so Windows does not need Python on the host) ----
docker cp "%~dp0add_go.py" %CONTAINER%:/tmp/add_go.py >nul
if errorlevel 1 ( echo [ERROR] Could not copy add_go.py into the container. & exit /b 1 )
docker cp "%~dp0gunzip.py" %CONTAINER%:/tmp/gunzip.py >nul
if errorlevel 1 ( echo [ERROR] Could not copy gunzip.py into the container. & exit /b 1 )

REM ---- Import each table; stop immediately on the first failure --------------
for %%B in (%ORDER%) do (
  call :import_one %%B
  if errorlevel 1 (
    echo.
    echo [ERROR] Import stopped at %%B. See the message above.
    exit /b 1
  )
)

echo.
echo ===============================================
echo  Done. All data imported successfully.
echo ===============================================
exit /b 0

:import_one
set "BASE=%~1"
set "SRC="
set "GZ="

REM Clear any leftover temp files from a previous table
docker exec %CONTAINER% sh -c "rm -f /tmp/_in.sql /tmp/_in.sql.gz /tmp/_fixed.sql" >nul 2>&1

REM Find file (exact or with timestamp suffix). IMPORTANT: verify the REAL
REM extension with %%~xF, because on Windows "*.sql" also matches "*.sql.gz"
REM via 8.3 short names (e.g. LOANS_~1.SQL) -- see review notes.
if exist "%SQL_DIR%\%BASE%.sql" (
  set "SRC=%SQL_DIR%\%BASE%.sql"
) else (
  for %%F in ("%SQL_DIR%\%BASE%*.sql") do if /i "%%~xF"==".sql" set "SRC=%%~fF"
)
if not defined SRC (
  for %%F in ("%SQL_DIR%\%BASE%*.sql.gz") do if /i "%%~xF"==".gz" set "GZ=%%~fF"
)

REM Missing file: only allrawloanstat is optional; anything else is an error
if not defined SRC if not defined GZ (
  if /i "%BASE%"=="allrawloanstat" (
    echo [SKIP] %BASE% - optional file, not included in this repo
    exit /b 0
  )
  echo [ERROR] Required file for "%BASE%" not found in %SQL_DIR%
  echo         Expected: %BASE%.sql  or  %BASE%*.sql  or  %BASE%*.sql.gz
  exit /b 1
)

if defined GZ (
  REM ---- Compressed file: copy .gz into container, decompress + GO-batch INSIDE it ----
  echo.
  echo -^> Importing (compressed): !GZ!
  docker cp "!GZ!" %CONTAINER%:/tmp/_in.sql.gz >nul
  if errorlevel 1 ( echo [ERROR] Could not copy !GZ! into the container. & exit /b 1 )
  docker exec %CONTAINER% python3 /tmp/gunzip.py /tmp/_in.sql.gz
  if errorlevel 1 ( echo [ERROR] Could not decompress the file inside the container. & exit /b 1 )
  docker exec %CONTAINER% python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql %BATCH_SIZE%
  if errorlevel 1 ( echo [ERROR] Could not add GO separators for %BASE%. & exit /b 1 )
) else (
  REM ---- Plain .sql file: copy into container and GO-batch ----
  echo.
  echo -^> Importing: !SRC!
  docker cp "!SRC!" %CONTAINER%:/tmp/_in.sql >nul
  if errorlevel 1 ( echo [ERROR] Could not copy !SRC! into the container. & exit /b 1 )
  docker exec %CONTAINER% python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql %BATCH_SIZE%
  if errorlevel 1 ( echo [ERROR] Could not add GO separators for %BASE%. & exit /b 1 )
)

REM Import the fixed file
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -d "%DATABASE%" -C -b -i /tmp/_fixed.sql
if errorlevel 1 ( echo [ERROR] SQL import failed for %BASE%. & exit /b 1 )
echo    OK: %BASE%
exit /b 0
