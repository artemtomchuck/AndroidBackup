<#
    Run backup of Android applications.
    Input:
      *) list of Android applications and other configuration parameters
      *) mostly all configuration parameters are stored in user-specific configuration file "C:\Users\<username>\AppData\Roaming\AndroidBackup\Settings.json". So this program theoretically can be used by multiple users on the same computer
      *) some configuration parameters are passed as input arguments of this powershell-script
    Output:
      *) note: mostly all $Variables mentioned below are taken based on configuration file. Some $Variables may be parameters of this powershell-script
      *) output archives located in $AndroidVmOutputFolderFullpath
      *) separate archive is created for each application from $AndroidVmApplicationsForBackupList
      *) format of output archives: $AndroidBackupCurrentRunIdentifier_$AndroidVmApplicationName.cpio
#>

param (
    [Parameter(Mandatory=$True)] [string]$AndroidBackupCurrentRunIdentifier # used to mark output archives with application data. Typically you want prefix your archives with run timestamp
)

function Write-LogMessage {
    param (
        [Parameter(Mandatory=$True)] [string]$LogMessage
    )
    
    $CurrentLogEntryTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fffffff"
    Write-Output ""
    Write-Output "$($CurrentLogEntryTimestamp) (host time) AndroidBackupLogger: $($LogMessage)"
}


function Start-Wait {
    param (
        [Parameter(Mandatory=$True)] [int]$Seconds,
        [string]$Comment
    )

    $LogMessage = "waiting $($Seconds) seconds"

    if ($Comment) {
        $LogMessage += " $($Comment)"
    }

    Write-LogMessage $LogMessage
    Start-Sleep $Seconds
}

function Initialize-AndroidVmIpAddressScriptVariable {
    # get mac-address by vmname
    $AndroidVmMacAddressLowerCaseNoDash = ((Get-VM | Where-Object{$_.VMName -eq $AndroidVmName} | Get-VMNetworkAdapter | Select-Object -ExpandProperty MacAddress).ToLower() -replace "-","")
    
    Write-LogMessage "set AndroidVmMacAddress `"$($AndroidVmMacAddressLowerCaseNoDash)`" based on AndroidVmName"

    # get ip-address by mac-address. We don't need to store this ip in config if we can get it based on some other config parameter. Moreover it is difficult to make static ip in hyper-v so it is easier to get it by vmname dynamically
    $AndroidVmIpAddressesWithSameMacAddressList = (Get-NetNeighbor | Select-Object @{
        label='MacAdressLowerCaseNoDash'
        expression={$_.LinkLayerAddress.ToLower() -replace "-",""}
    }, IPAddress | Where-Object{$_.MacAdressLowerCaseNoDash -eq $AndroidVmMacAddressLowerCaseNoDash} | Select-Object -ExpandProperty IPAddress)

    Write-LogMessage "found the following IpAddresses per single mac-address:"
    Write-Output $AndroidVmIpAddressesWithSameMacAddressList # Write-Output used directly in order to preserve table-formatting
    
    # yes, it is possible to have multiple IP addresses per single mac-address. At least this was reproduced on development environment with hyper-v VM.
    # So we will use first IP which is pingable.
    # In most expected case when we have only single IP per mac-address we will just test if IP is reachable before using it
    foreach ($CurrentAndroidVmIpAddress in $AndroidVmIpAddressesWithSameMacAddressList)
    {
        if (Test-Connection -ComputerName $CurrentAndroidVmIpAddress -Quiet)
        {
            # this IP address is pinged. Therefore use it and do not check other addresses
            Write-LogMessage "set AndroidVmIpAddress to `"$($CurrentAndroidVmIpAddress)`" based on AndroidVmMacAddress and because this IP was the first pingable in the whole list of IPs with the same mac-address"
            $OutputAndroidVmIpAddress = $CurrentAndroidVmIpAddress
            break
        } else {
            Write-LogMessage "IpAddress = `"$($CurrentAndroidVmIpAddress)`" is not reachable. Therefore we won't use it"
        }   
    }

    # only not null and non-empty strings can be valid IP. String will spaces only does not count
    if ($OutputAndroidVmIpAddress -And $OutputAndroidVmIpAddress.Trim()) {
        $script:AndroidVmIpAddress = $OutputAndroidVmIpAddress
    }
    else {
        throw "Initialize-AndroidVmIpAddressVariable function can't assign real IP address. OutputAndroidVmIpAddress value = `"$($OutputAndroidVmIpAddress)`""
    }
}

function Initialize-HostEnvironmentScriptVariables {
    param (
        [Parameter(Mandatory=$True)] [string]$Context
    )
    
    switch ( $Context )
    {
        "NoDependency" {
            $AndroidBackupApplicationName = "AndroidBackup"

            # we store configs in special Windows-folder for such purposes. These user config settings can be transferred across multiple computers. Therefore we use C:\Users\<username>\AppData\Roaming and not C:\Users\<username>\AppData\Local
            $AndroidBackupSettingsConfigFileFullpath = "$($env:APPDATA)\$($AndroidBackupApplicationName)\Settings.json"

            Write-LogMessage "read settings from config file `"$($AndroidBackupSettingsConfigFileFullpath)`""
            $AndroidBackupSettingsFromConfigFile = Get-Content -Path $AndroidBackupSettingsConfigFileFullpath | ConvertFrom-Json

            # It will be convenient to see configuration in log.
            # If for example some previous run was ok, but after config change there is a new failure. And you want to check from logs which configuration in the past gave succesfull run.
            Write-LogMessage "print settings from config file `"$($AndroidBackupSettingsConfigFileFullpath)`""
            # not putting this config content directly into Write-LogMessage function on purpose. With Write-Output the content will be shown in more readable form
            Write-Output $AndroidBackupSettingsFromConfigFile

            ### direct variables from config ###
            $script:AndroidVmName = $AndroidBackupSettingsFromConfigFile.AndroidVmName
            $script:AndroidVmSshHostKeyFingerprint = $AndroidBackupSettingsFromConfigFile.AndroidVmSshHostKeyFingerprint
            $script:AndroidVmSshUsername = $AndroidBackupSettingsFromConfigFile.AndroidVmSshUsername
            $script:AndroidVmSshUserPuttyPrivateKeyFullpathInHostSystem = $AndroidBackupSettingsFromConfigFile.AndroidVmSshUserPuttyPrivateKeyFullpathInHostSystem
            $script:AndroidVmOutputFolderFullpath = $AndroidBackupSettingsFromConfigFile.AndroidVmOutputFolderFullpath
            $script:AndroidVmApplicationsForBackupList = $AndroidBackupSettingsFromConfigFile.AndroidVmApplicationsForBackupList
            
            ### standalone variables ### 
            $script:HostTmpFolderFullpath = "$($env:TEMP)\$($AndroidBackupApplicationName)"
            $script:HostTmpScriptFolderOfCurrentBackupFullpath = "$($HostTmpFolderFullpath)\$($AndroidBackupCurrentRunIdentifier)\ScriptsForAndroidVm"
            $AndroidTmpFolderDefaultLocationFullpath = "/data/local/tmp" # (kind of) default location of tmp folder in Android
            $script:AndroidVmTmpFolderForAndroidBackupFullpath = "$($AndroidTmpFolderDefaultLocationFullpath)/$($AndroidBackupApplicationName)" 

            ### derivative variables from config snd standalone ###
            $script:AndroidVmTmpDataFolderOfCurrentBackupFullpath = "$($AndroidVmTmpFolderForAndroidBackupFullpath)/$($AndroidBackupCurrentRunIdentifier)"
        }
        "AfterAndroidVmStart" {
            # we have to initialize IP address when VM is already booted (because we can't be always sure about IP address of VM until it is booted).
            Initialize-AndroidVmIpAddressScriptVariable
        }
        default {
            throw "Initialize-HostEnvironmentScriptVariables function does not recogize Context parameter with value = `"$($Context)`""
        }
    }
}

function Initialize-HostEnvironment {
    param (
        [Parameter(Mandatory=$True)] [string]$Context
    )

    switch ( $Context )
    {
        "NoDependency" {
            # increase console output width in order to more conveniently read logs (avoid unnecessary line breaks).
            # By default the width is probably 120 (at least on testing/development system) which is typically not enough.
            $ConsoleOutputWidth=1000
            MODE $ConsoleOutputWidth
            Write-LogMessage "set width of console output to $ConsoleOutputWidth"
        }
        "AfterEnvironmentVariablesInitialization" {
            Write-LogMessage "remove (if exists) previous run content of host tmp folder `"$($HostTmpFolderFullpath)`""
            Get-ChildItem -Path $HostTmpFolderFullpath -Include * | Remove-Item -Recurse -Force
        
            Write-LogMessage "create (if doesn't yet exist) host tmp folder `"$($HostTmpFolderFullpath)`""
            New-Item $HostTmpFolderFullpath -ItemType "directory" -Force
        
            # powershell code won't automatically create this folder when using Set-Content for new files in $HostTmpScriptFolderOfCurrentBackupFullpath. So we have to create this folder here once at the beginning of backup process
            Write-LogMessage "create host tmp script folder of current backup `"$($HostTmpScriptFolderOfCurrentBackupFullpath)`""
            New-Item $HostTmpScriptFolderOfCurrentBackupFullpath -ItemType "directory" -Force    
        }
        default {
            throw "Initialize-HostEnvironment function does not recogize Context parameter with value = `"$($Context)`""
        }
    }
}

function Invoke-SshCommandOnAndroidVm {
    param (
        [Parameter(Mandatory=$True)] [string]$SshCommandOnAndroidVm
    )

    $CurrentSshCommandScriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmssfffffff" # we use timestamp in script naming to conveniently see the sequence of scripts (e.g. for debug purposes)
    $CurrentSshCommandScriptGuid = (New-Guid).ToString() # we use guid in script naming to prevent potential collisions
    $CurrentSshCommandScriptFullpath = "$($HostTmpScriptFolderOfCurrentBackupFullpath)\$($CurrentSshCommandScriptTimestamp)_$($CurrentSshCommandScriptGuid).sh"
    
    # create Android script for current ssh command. We should use linux end of line separator "`n" when printing to file
    Set-Content -NoNewLine -Path $CurrentSshCommandScriptFullpath -Value (
      (
        $SshCommandOnAndroidVm -join "`n"
      ) + "`n"
    )
     
    # Notes:
    # *) -batch option is used to suppress any interactive prompts from Android VM because there is no intention in automated script to provide input for any prompts
    # *) theoretically you can also setup some saved session here to avoid reconnection for each plink call. But in current case the commands are run not that much often and it definitively does not affect performance very much. Performance is not a key in current backup application
    # *) we execute command from temporary file because enclosing handling is more stable in printed files compared to passing commands from variables directly into plink
    # *) yes, we could theoretically build one big local (stored in Windows) shell-script and execute it via plink, but there is some limit in plink (approximately 4096 symbols per local script file).
    #    So in order to avoid reaching this limit I had to split all Android code into atomic commands so in Android we execute only concrete small commands, but the whole long workflow is executed on powershell side.
    #    Yes, we could also transfer local-shell file to Android and execute it on Android side so script size limit would not be relevant anymore. But there is huge effort required to execute root script on Android.
    #    During each script run we would have to copy this script into some root folder location. For that we have to remount root location into write-mode, make this script executable, execute it and then remount back root folder to readonly-mode. It is complicated process.
    #    Also we can't just store constantly script in root directory because this script will be erased each Android reboot (each Android reboot root folder is restored from some factory image. It is complicated to change this factory image via including my script into this image)
    #    And finally we can't execute script which is not in root folder (this is according to some Android restriction). So it is not possible to execute script from some user mounted directory (user mounted directory is not restored each Android reboot).
    #    Due to complexities described above I decided to keep the main flow in powershell. Anyway if we want to keep the main flow in Android then instead of shell-script it would be better to write some real Android application (e.g. using Java) so on powershell side we can just call this Android-application without any generated script transfer
    # *) -hostkey option will make sure that if IP address was changed (we use dynamic IP addresses) then we will be able to recognize that host is still the same (and consequently we also won't get any error messages like "The server's host key is not cached...")
    #    we can of course avoid here -hostkey parameter and blindly accept any hostkey (in reality we will have multiple ip addresses bounded to the same hostkey due to frequent IP changes).
    #    This would allow us to store only VMname in configs to automatically identify host of ssh connection. But this is bad security practice to automatically accept any hostkey for new unknown (dynamically generated) IP. So better to provide redundant parameter instead of compromising security by avoiding redundant parameter.
    #    Since it is not possible to always accept particular hostkey for any IP address (plink stores its allowed hostkey per ip only), we have to provide this hostkey during each call.
    plink -batch -ssh "$($AndroidVmSshUsername)@$($AndroidVmIpAddress)" -i $AndroidVmSshUserPuttyPrivateKeyFullpathInHostSystem -hostkey $AndroidVmSshHostKeyFingerprint -m $CurrentSshCommandScriptFullpath
}

function Invoke-SshCommandOnAndroidVmAsSuperuser {
    param (
        [Parameter(Mandatory=$True)] [string]$SshCommandOnAndroidVmAsSuperuser
    )

    # replace " occurences with \" for Android (linux) escaping. Because if we have double quotes in command then we will have to escape them so next su -c "command" in double quotes will be interpreted correctly
    $SshCommandOnAndroidVmAsSuperuserEscaped = $SshCommandOnAndroidVmAsSuperuser.Replace("`"","\`"")
    
    Invoke-SshCommandOnAndroidVm "su -c `"$($SshCommandOnAndroidVmAsSuperuserEscaped)`""
}

function Stop-AndroidVmApplication {
    param (
        [Parameter(Mandatory=$True)] [string]$AndroidVmApplicationName
    )
    
    Write-LogMessage "stop Android VM application `"$($AndroidVmApplicationName)`""
    Invoke-SshCommandOnAndroidVmAsSuperuser "am force-stop `"$($AndroidVmApplicationName)`""
    
    # Let's wait some time to 'stabilize' database after application was stopped. Just want to make sure that process which writes into database will have enough time to stop completely
    # This is in order to make sure that application completely stopped. Not sure if this 100% needed, but let it be just in case
    Start-Wait 10 "after stopping `"$($AndroidVmApplicationName)`" Android VM application"
}

function Start-AndroidVmApplication {
    param (
        [Parameter(Mandatory=$True)] [string]$AndroidVmApplicationName
    )
    
    Write-LogMessage "start Android VM application `"$($AndroidVmApplicationName)`""
    Invoke-SshCommandOnAndroidVmAsSuperuser "monkey -p `"$($AndroidVmApplicationName)`" 1"
}

function Save-OutputArchiveWithAndroidVmApplicationData {
    param (
        [Parameter(Mandatory=$True)] [string]$AndroidVmApplicationName
    )

    $AndroidVmApplicationDataFolderFullpath = "/data/data/$($AndroidVmApplicationName)"
    $AndroidVmApplicationTmpDataFolderOfCurrentBackupFullpath = "$($AndroidVmTmpDataFolderOfCurrentBackupFullpath)/$($AndroidVmApplicationName)"
    $AndroidVmOutputArchiveExtension = "cpio"
    $AndroidVmApplicationArchiveBaseName = "$($AndroidVmApplicationName).$($AndroidVmOutputArchiveExtension)"
    $AndroidVmApplicationIntermediateArchiveFullpath = "$($AndroidVmTmpDataFolderOfCurrentBackupFullpath)/$($AndroidVmApplicationArchiveBaseName)"
    $AndroidVmApplicationResultArchiveFullpath = "$($AndroidVmOutputFolderFullpath)/$($AndroidBackupCurrentRunIdentifier)_$($AndroidVmApplicationArchiveBaseName)"

    Write-LogMessage "copy data of `"$($AndroidVmApplicationName)`" Android VM application from root data folder `"$($AndroidVmApplicationDataFolderFullpath)`" to Android VM tmp-folder `"$($AndroidVmApplicationTmpDataFolderOfCurrentBackupFullpath)`""
    # dot after source path is intended to copy also hidden files. But it seems that Android version of cp also copies hidden files even without specifying dot. But anyway let's leave dot here to imply our intention to copy all files even hidden.
    # Target directory will be created during copy
    Invoke-SshCommandOnAndroidVmAsSuperuser "cp -R `"$($AndroidVmApplicationDataFolderFullpath)/.`" `"$($AndroidVmApplicationTmpDataFolderOfCurrentBackupFullpath)`""

    Write-LogMessage "create intermediate archive `"$($AndroidVmApplicationIntermediateArchiveFullpath)`" of `"$($AndroidVmApplicationName)`" Android VM application files in Android VM tmp-folder based on `"$($AndroidVmApplicationTmpDataFolderOfCurrentBackupFullpath)`" in Android VM tmp-folder"
    # From technical point of view this command does the following: get full hierarchy of application directory and add its content to result cpi archive.
    # Yes, cpio is not very convenient (you can't archive the whole folder with only cpio command like it is possible in tar. You have to loop over files in order to fill archive).
    # We should set current directory to the input archive folder in Android so find command will show only relative path. Otherwise (if providing fullpath to find command) we will have fullpath in arhive structure, but we need only relative path in archive
    Invoke-SshCommandOnAndroidVmAsSuperuser "cd `"$($AndroidVmApplicationTmpDataFolderOfCurrentBackupFullpath)`"; find ./ -print -depth | cpio -ov > `"$($AndroidVmApplicationIntermediateArchiveFullpath)`";"
    # Notice: you may wonder why not so much popular cpio arhiver is used here. The reason is because I encountered some weird bug with default installation of popular tar archiver on Android VM (version android-x86_64-8.1-r6)
    # when executing the following command "tar -zcvf '$($AndroidVmTmpDataFolderOfCurrentBackupFullpath)/$($AndroidVmApplicationName).tar.gz' -C '$($AndroidVmTmpDataFolderOfCurrentBackupFullpath)/$($AndroidVmApplicationName)' ."
    # via Invoke-SshCommandOnAndroidVm function then sometimes corrupted archive is created (e.g. it was constantly reproduced for arhive of "io.timetrack.timetrackapp" application). Some files were missing in this archive.
    # However when running the same command in simple ssh session (e.g. via putty) then the issue is not reproduced. So there is probably some integration bug of plink (plink is used in RunSshCommandOnAndroidVm) in conjunction with tar version in Android Vm
    # I didn't manage to reproduce the issue if running the same command via Invoke-SshCommandOnAndroidVm with the same "io.timetrack.timetrackapp" archive on Ubuntu 20.04. On Ubuntu archive was created succesully (I delivered "io.timetrack.timetrackapp" folder into Ubuntu via sftp).
    # Therefore conclusion: there is somewhere bug on Android side which prevents me to use tar program together with plink. So instead of tar I have to use something else which is available on Android VM out of box (because in order to keep dependencies at a minimum level I try to avoid installing additional software on Android Vm).
    # The only other available arhiver in standard distribution of android-x86_64-8.1-r6 was cpio (at least the only one I found). So I use cpio. cpio does not have the same issue as tar had.

    # copy archive into sync area where this new file should be uploaded into cloud storage (GDrive, Dropbox, OneDrive etc). Or you may mount to $AndroidVmOutputFolderFullpath host system drive to store results somewhere outside VM
    Write-LogMessage "copy intermediate archive `"$($AndroidVmApplicationIntermediateArchiveFullpath)`" of Android VM application `"$($AndroidVmApplicationName)`" into prefixed result archive `"$($AndroidVmApplicationResultArchiveFullpath)`" in Android VM sync area"
    Invoke-SshCommandOnAndroidVmAsSuperuser "cp `"$($AndroidVmApplicationIntermediateArchiveFullpath)`" `"$($AndroidVmApplicationResultArchiveFullpath)`""

    # we don't remove content of tmp dir after run. So if something goes wrong then we will have left overs in this tmp folder which can be analysed
}

function Backup-AndroidVmApplication {
    param (
        [Parameter(Mandatory=$True)] [string]$AndroidVmApplicationName
    )

    Write-LogMessage "start backup of `"$($CurrentAndroidVmApplication)`" Android VM application"

    # stop application. Because if we start application in next command and this application was running in background (or was open)
    # then based on testings some applications (e.g. "io.timetrack.timetrackapp") will never sync data after opening from already opened state. But if we stop application and then reopen it then data sync will occur
    Stop-AndroidVmApplication $AndroidVmApplicationName
    
    Start-AndroidVmApplication $AndroidVmApplicationName

    Start-Wait 10 "with assumption that 10 seconds will be enough for `"$($AndroidVmApplicationName)`" Android VM application to sync its cloud-account data with local Android VM db"

    # stop application so it won't be writing into db file (I want to have DB file which will not be changed whenever I will copy it later)
    Stop-AndroidVmApplication $AndroidVmApplicationName

    Save-OutputArchiveWithAndroidVmApplicationData $AndroidVmApplicationName
    
    # start application back again after backup. The purpose of this is to have application working in background when other applications will perform their backups in parallel.
    # Having application run in background will increase chance to have the more updated data in the next backup run of this application
    # Just in case if waiting 10 seconds was not enough to synchonize app data in current run then this up time will possible help to sync data in the next run
    Start-AndroidVmApplication $AndroidVmApplicationName
    
    Write-LogMessage "finish backup of `"$($CurrentAndroidVmApplication)`" Android VM application"
}

function Initialize-AndroidVmEnvironment {
    Write-LogMessage "remove (if exists) previous run content of Android VM tmp folder `"$($AndroidVmTmpFolderForAndroidBackupFullpath)`""
    Invoke-SshCommandOnAndroidVmAsSuperuser "rm -rf `"$($AndroidVmTmpFolderForAndroidBackupFullpath)/`"*"

    Write-LogMessage "create (if doesn't yet exist) Android VM tmp folder `"$($AndroidVmTmpFolderForAndroidBackupFullpath)`""
    Invoke-SshCommandOnAndroidVmAsSuperuser "mkdir -p `"$($AndroidVmTmpFolderForAndroidBackupFullpath)`""

    Write-LogMessage "create Android VM tmp folder of current backup `"$($AndroidVmTmpDataFolderOfCurrentBackupFullpath)`" to copy here applications data of current run"
    Invoke-SshCommandOnAndroidVmAsSuperuser "mkdir -p `"$($AndroidVmTmpDataFolderOfCurrentBackupFullpath)`""
}

function Start-AndroidVm {
    Write-LogMessage "start Android VM `"$($AndroidVmName)`""
    Start-VM -Name $AndroidVmName
    Start-Wait 60 "until Android VM `"$($AndroidVmName)`" is booted. Assuming this time is enough for VM being completely booted and SSH server on VM being automatically started"
}

function Stop-AndroidVm {
    Write-LogMessage "stop Android VM `"$($AndroidVmName)`""
    Stop-VM -Name $AndroidVmName
}

function Backup-SelectedListOfAndroidVmApplications {

    foreach ($CurrentAndroidVmApplication in $AndroidVmApplicationsForBackupList)
    {
        Backup-AndroidVmApplication $CurrentAndroidVmApplication
    }

    # this step is needed only if your output folder is mapped to some cloud storage. You don't want to stop Android VM if sync process (which is running on Android) hasn't yet synced your data.
    # if your output folder is mapped to some simple folder (e.g. mapped to Windows host folder via Samba server) then this step is not necessary
    # If needed then you can also create some new parameter in Settings.json which will define if you have to wait. This can be just an integer parameter with seconds

    Start-Wait 180 "so sync process will have enough time to upload local files from Android VM output folder `"$($AndroidVmOutputFolderFullpath)`" into cloud storage"
}

function Start-AndroidBackup {
    Initialize-HostEnvironment "NoDependency"

    Write-LogMessage "RunAndroidBackup begin"

    Initialize-HostEnvironmentScriptVariables "NoDependency"
    Initialize-HostEnvironment "AfterEnvironmentVariablesInitialization"

    Start-AndroidVm
    Initialize-HostEnvironmentScriptVariables "AfterAndroidVmStart"
    Initialize-AndroidVmEnvironment

    Backup-SelectedListOfAndroidVmApplications

    Stop-AndroidVm

    Write-LogMessage "RunAndroidBackup end"
}

# entry point
Start-AndroidBackup

