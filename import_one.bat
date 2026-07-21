@echo off
REM ============================================================================
REM  import_one.bat  -  Import ONE .sql (or .sql.gz) file into SQL Server (Docker)
REM  For Windows
REM
REM  Use this for a standalone table that does NOT depend on any other table.
REM  The table name comes from the CREATE TABLE statement inside the .sql file.
REM
REM  Problem it fixes: exported .sql files have NO "GO" batch separators, so
REM  sqlcmd sends the whole file as one batch and the connection drops
REM  (TCP Provider: Error code 0x68). This script inserts GO automatically.
REM
REM  How to use:
REM    import_one.bat  path\to\yourfile.sql
REM    import_one.bat  path\to\yourfile.sql.gz
REM ============================================================================
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ---------- Settings (edit to match your machine) --------------------------
if "%CONTAINER%"==""    set "CONTAINER=sql_server"
if "%SA_PASSWORD%"==""  set "SA_PASSWORD=Passw0rd123456"
if "%DATABASE%"==""     set "DATABASE=TestDB"
if "%BATCH_SIZE%"==""   set "BATCH_SIZE=500"
set "SQLCMD=/opt/mssql-tools18/bin/sqlcmd"
REM ---------------------------------------------------------------------------

REM ---- Check the file argument ----------------------------------------------
if "%~1"=="" (
  echo Usage: import_one.bat ^<path\to\file.sql^>
  echo    or: import_one.bat ^<path\to\file.sql.gz^>
  exit /b 1
)
set "SRC=%~f1"
if not exist "%SRC%" (
  echo [ERROR] File not found: %SRC%
  exit /b 1
)

REM Decide whether the input is compressed (real extension .gz)
set "IS_GZ="
if /i "%~x1"==".gz" set "IS_GZ=1"

echo ===============================================
echo  Importing ONE file into SQL Server
echo    Container : %CONTAINER%
echo    Database  : %DATABASE%
echo    File      : %SRC%
echo    Batch size: insert GO every %BATCH_SIZE% statements
echo ===============================================

REM ---- Check helper scripts exist next to this .bat -------------------------
if not exist "%~dp0add_go.py" (
  echo [ERROR] add_go.py not found next to this script. Please extract the whole folder.
  exit /b 1
)
if "%IS_GZ%"=="1" if not exist "%~dp0gunzip.py" (
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

REM ---- Check python3 exists inside the container ----------------------------
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

REM ---- Copy helpers into the container --------------------------------------
docker cp "%~dp0add_go.py" %CONTAINER%:/tmp/add_go.py >nul
if errorlevel 1 ( echo [ERROR] Could not copy add_go.py into the container. & exit /b 1 )
if "%IS_GZ%"=="1" (
  docker cp "%~dp0gunzip.py" %CONTAINER%:/tmp/gunzip.py >nul
  if errorlevel 1 ( echo [ERROR] Could not copy gunzip.py into the container. & exit /b 1 )
)

REM ---- Clear leftover temp files --------------------------------------------
docker exec %CONTAINER% sh -c "rm -f /tmp/_in.sql /tmp/_in.sql.gz /tmp/_fixed.sql" >nul 2>&1

REM ---- Copy input, decompress (if needed) + GO-batch INSIDE the container ----
if "%IS_GZ%"=="1" (
  echo.
  echo -^> Importing (compressed): %SRC%
  docker cp "%SRC%" %CONTAINER%:/tmp/_in.sql.gz >nul
  if errorlevel 1 ( echo [ERROR] Could not copy the file into the container. & exit /b 1 )
  docker exec %CONTAINER% python3 /tmp/gunzip.py /tmp/_in.sql.gz
  if errorlevel 1 ( echo [ERROR] Could not decompress the file inside the container. & exit /b 1 )
  docker exec %CONTAINER% python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql %BATCH_SIZE%
  if errorlevel 1 ( echo [ERROR] Could not add GO separators. & exit /b 1 )
) else (
  echo.
  echo -^> Importing: %SRC%
  docker cp "%SRC%" %CONTAINER%:/tmp/_in.sql >nul
  if errorlevel 1 ( echo [ERROR] Could not copy the file into the container. & exit /b 1 )
  docker exec %CONTAINER% python3 /tmp/add_go.py /tmp/_in.sql /tmp/_fixed.sql %BATCH_SIZE%
  if errorlevel 1 ( echo [ERROR] Could not add GO separators. & exit /b 1 )
)

REM ---- Import the fixed file -------------------------------------------------
docker exec %CONTAINER% %SQLCMD% -S localhost -U SA -P "%SA_PASSWORD%" -d "%DATABASE%" -C -b -i /tmp/_fixed.sql
if errorlevel 1 ( echo [ERROR] SQL import failed. & exit /b 1 )

echo.
echo ===============================================
echo  Done. File imported successfully.
echo ===============================================
exit /b 0
