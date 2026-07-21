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
REM    2) Open Command Prompt in this folder
REM    3) Run:   import_all.bat
REM ============================================================================
setlocal enabledelayedexpansion

REM ---------- Settings (edit to match your machine) --------------------------
if "%CONTAINER%"=="" set CONTAINER=sql_server
if "%SA_PASSWORD%"=="" set SA_PASSWORD=Passw0rd123456
if "%DATABASE%"=="" set DATABASE=TestDB
if "%SQL_DIR%"=="" set SQL_DIR=.\sql
if "%BATCH_SIZE%"=="" set BATCH_SIZE=500
set SQLCMD=/opt/mssql-tools18/bin/sqlcmd
REM ---------------------------------------------------------------------------

echo ===============================================
echo  Importing data into SQL Server
echo    Container : %CONTAINER%
echo    Database  : %DATABASE%
echo    Batch size: insert GO every %BATCH_SIZE% statements
echo ===============================================

REM Import order: dimensions first, then facts
set ORDER=application_type_dim emp_length_dim home_ownership_dim issue_d_dim loan_status_dim loans_fact allrawloanstat

REM Check container is running
docker ps --format "{{.Names}}" | findstr /x "%CONTAINER%" >nul
if errorlevel 1 (
  echo [ERROR] Container "%CONTAINER%" is not running. Check with: docker ps
  exit /b 1
)

REM Check SQL Server connection
echo -^> Checking SQL Server connection ...
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -C -Q "SELECT 1" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Cannot connect to SQL Server. Check SA password or container status.
  exit /b 1
)
echo    Connected OK

REM Create database if missing
echo -^> Ensuring database "%DATABASE%" exists ...
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -C -Q "IF DB_ID('%DATABASE%') IS NULL CREATE DATABASE [%DATABASE%];" >nul
echo    Ready

REM Copy the GO-batching helper into the container once
docker cp "%~dp0add_go.py" %CONTAINER%:/tmp/add_go.py

for %%B in (%ORDER%) do call :import_one %%B

echo.
echo ===============================================
echo  Done. All data imported successfully.
echo ===============================================
goto :eof

:import_one
set BASE=%~1
set SRC=
set GZ=

REM Find file (exact or with timestamp suffix), .sql first then .sql.gz
if exist "%SQL_DIR%\%BASE%.sql" (
  set SRC=%SQL_DIR%\%BASE%.sql
) else (
  for %%F in ("%SQL_DIR%\%BASE%*.sql") do set SRC=%%F
)
if "!SRC!"=="" (
  for %%F in ("%SQL_DIR%\%BASE%*.sql.gz") do set GZ=%%F
)
if "!SRC!"=="" if "!GZ!"=="" (
  echo [SKIP] %BASE% - file not found in %SQL_DIR%
  goto :eof
)

REM Decompress .gz once if needed
if not "!GZ!"=="" (
  echo -^> Decompressing: !GZ!
  python gunzip.py "!GZ!"
  set SRC=!GZ:.gz=!
)

echo.
echo -^> Importing: !SRC!

REM 1) Copy into container and add GO every N statements
docker cp "!SRC!" %CONTAINER%:/tmp/_in.sql
docker exec %CONTAINER% python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql %BATCH_SIZE%

REM 2) Import the fixed file
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -d "%DATABASE%" -C -b -i /tmp/_fixed.sql
echo    OK: !SRC!
goto :eof
