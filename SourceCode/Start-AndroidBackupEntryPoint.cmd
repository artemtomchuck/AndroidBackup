REM ############################################################################################
REM Purpose: entry point for starting AndroidBackup application
REM See detailed description of input/output in comments of %cd%\Start-AndroidBackup.ps1 file
REM Logs are stored in C:\Users\<username>\AppData\Local\AndroidBackup\Logs
REM --
REM Notes:
REM the only reason why I don't want to use powershell as an entry point is because it is much easier to run cmd-script.
REM You surely won't have to provide any arguments into this cmd-command and you don't have to bother whether your system allows to execute powershell by clicking powershell-scripts in Windows Explorer
REM You can just click cmd file and it should be immediately executed
REM But from perspective of development it is much easier to use powershell because cmd is not so much convenient language. So I use powershell for everything else except entry point
REM ############################################################################################


REM change encoding to UTF-8. So if any non-English output appears then it will be more likely treated correctly
chcp 65001

REM get timestamp is much easier in powershell compared to get it in pure cmd. In cmd getting correct yyyyMMdd-HHmmss mask depends on environment locale
REM Therefore we will initialize cmd variable from powershell command output which should be universal for every environment
FOR /F "tokens=* USEBACKQ" %%F IN (`powershell Get-Date -Format "yyyyMMdd-HHmmss"`) DO (
SET TimestampOfCurrentRun=%%F
)

REM we store logs in special Windows-folder for such purposes. These user log-files cannot be transferred across multiple computers - it least it does not make a lot of sense.
REM Therefore we use C:\Users\<username>\AppData\Local and not C:\Users\<username>\AppData\Roaming
SET AndroidBackupLogFolder="%LocalAppData%\AndroidBackup\Logs"

if not exist %AndroidBackupLogFolder% mkdir %AndroidBackupLogFolder%

SET FolderWithThisCmdScript=%~dp0
SET MainPowershellFileExecutableFullPath="%FolderWithThisCmdScript%\Start-AndroidBackup.ps1"
SET AndroidBackupLogFileOfCurrentRun="%AndroidBackupLogFolder%\%TimestampOfCurrentRun%.log"

REM the main call
powershell -executionpolicy bypass -File %MainPowershellFileExecutableFullPath% -AndroidBackupCurrentRunIdentifier %TimestampOfCurrentRun% > %AndroidBackupLogFileOfCurrentRun% 2>&1

