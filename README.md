# AndroidBackup

# Purpose
Create backup of Android applications

# Use case
Suppose you have unrooted Android device which is used in your every day life. And you don't want to root this device (e.g. in order to keep warranty and on-the-fly updates from your device vendor).

Also you have critical applications installed in your device which data you want to backup regularly.

To accomplish your goal of regular backup - there is no solution which you can apply on device itself to automatically backup your data on regular basis. Existing solutions (at least about which author was aware as of creating this software) require root on your device (but as mentioned above you don't want to root your device for some reason).

You may say that Google account do backup on daily basis of your application. Yes, it is true, but you are not in control of those backups from your Google account. You can't extract those backups directly from your account (it is possible to only restore backup into your device, but you can't see backup data in your file system) and moreover Google probably keeps only the latest backup of your application, but you want to keep the whole backup history (e.g. in order to have possibility restore your data at a point of or so month ago).

Solution to the problem above is to use current software.

Please note about limitation: this software only makes sense for applications which have cloud accounts. So applications for backup should have possiblity to transfer their data to different devices (e.g. most of Google Android applications can be used simulteneously on several devices. Once you made change in data in your main device - this change also will be visible on other devices after Google cloud account synchonization).

You may wonder why do you need to backup applications which already have cloud account. Yes, it is not necessary in case you rely completely your data to the application vendor. But everything can happen - e.g. your account compromised, your data/account was accidentally deleted. If you are paranoic about such things then this application is for you. Also your cloud application account typically doesn't let you to restore data history at certain point of time - so having backup will let you to do this.

# How does it work?
* You have to create Android VM on your computer and install here all necessary applications which you want to backup
* You use your main device as usual, change your data in application and all your data changes are transferred into Android VM by means of cloud account data synchonization (every application vendor implements its own mechanism of cloud data synchonization. As mentioned already - it is critical to have account data synchronization in application to be backed up. Applications without cloud accounts can't be backed up using this software)
* Your Android VM is rooted by design (you can download stock Android image which is already rooted. As your VM does not require on-the-fly updates or does not have any warranty - you can safely root it). So you have access to internal application data structure in your Android VM. The main idea of using VM is to move need for root from your regular device into VM (root is strictly needed for accessing internal data structures of your applications. Only by accesing those internal data structures you can create the backup). Otherwise if your regular device is already rooted then probably it will be more efficient to perform backups directly on your regular device (search some ready solutions in this case - e.g. Helium. Or you can adjust this code to be run directly on rooted device)
* Each time when you call your backup the following happens:
    * Android VM is started
    * All your applications are automatically started on this VM so they can sync their cloud account data
    * All your applications are stopped after some time in order to fix the internal data structures before backup so application won't change its data when backup in progress
    * All internal data of your applications are archived and transferred to output folder in your Android VM
    * You can get output archives with your application data. If you mount your output folders with arhives to some host-system folder then you can get your data outside VM and use it as a backup. Or you can map output folder into some cloud file storage (e.g. Dropbox, GoogleDrive, OneDrive etc) so all your backups are not only in host-system, but also additionally backed up in cloud storage
    * Android VM is stopped (because there is no need to keep VM constantly working)

# Setup
* Copy code into dedicated installation folder of this software (whole content of SourceCode folder). E.g. create folder C:\AndroidBackup and place the following files into this folder
    * Start-AndroidBackupEntryPoint.cmd
    * Start-AndroidBackup.ps1
* Create json-configuration file with application settings in C:\Users\<username>\AppData\Roaming\AndroidBackup\Settings.json by copying initial template version (see ConfigurationTemplates folder). Each user of computer can create its own instance of this backup application. And therefore configuration is separate for each user. Adjust configuration file with your desired parameters:
  * AndroidVmSshUsername - ssh username which will be used to invoke ssh-commands on Android VM. You will have to setup SSH server on Android VM (it will be described later)
  * AndroidVmSshHostKeyFingerprint - ssh host key fingerprint of your Android VM. This is needed for plink in order to identify if your ssh session is connected to expected host. You can get it when connecting to Android VM via Putty (during first connect you will see SSH finger print. Save it and use in this configuration). Or you can extract this fingerprint directly from VM somehow without connecting via SSH (e.g. by searching some public key file via Hyper-V GUI in internal Android file system)
  * AndroidVmSshUserPuttyPrivateKeyFullpathInHostSystem - full path to file with private key in Putty format. This key will be used for authentication when connecting your host to Android VM. You can use PuttyGen utility to generate such private key. Once private key generated and set into this parameter, you will also have to place respective public key into special folder of your SSH server on Android VM (SSH server configuration will be mentioned later)
  * AndroidVmName - name of your Android VM in hyper-v. This name will be used to identify your VM instance so it can be started and stopped. Also this parameter will help to dynamically identify IP address of Android VM
  * AndroidVmApplicationsForBackupList - the list of your applications which will be included into backup. These applications should be installed in your Android VM. Use official strict names of applications. E.g. for Google Keep the name is "com.google.android.keep". You can get this official name in address for PlayMarket link - e.g. in https://play.google.com/store/apps/details?id=com.google.android.keep. Or you can get this name in Android data folder /data/data/<your_application_name> - e.g. for Google Keep you can find its name in /data/data/com.google.android.keep. Do not use any spaces or any extra symbols in application name. The whole backup mechanism relies on correct and precise application name (e.g. application data folder is dynamically identified by application name using naming convetion, application is started by its strict name etc)
  * AndroidVmOutputFolderFullpath - the folder in Android VM where you will get output files with application backups. You can mount this folder to host-system so the output will be available in Windows. Or you can setup cloud sync for this folder directly in Android VM. So after new backup files are published in this output folder, the sync will upload new files into your desired cloud storage (e.g. you can use DriveSync Android application to sync with Google Drive, DropSync to sync with Dropbox etc)
  * Note: you may notice that obvious parameter is missing here - IP address of Android VM. But it is not needed to specify it here because code will get it dynamically based on AndroidVmName (AndroidVmName identifies uniquely macaddress. And by macaddress code can find IP address). By default hyper-v bind your Android VM to default network switch. And by default this default network switch uses local dynamic IP address. So if you want to have static IP for your VM then you will have to configure some non-default network switch and bind VM macaddress to static IP (or even use DHCP server which will handle your static IP). To overcome this complexity with static IP configuration the decision is to not create/use static IP at all. We will use default network switch from hyper-v and get assigned dynamic IP address automatically
* Create Android VM with the same name as in AndroidVmName configuration parameter
  * During initial development and installation author used android-x86_64-8.1-r6.iso from https://www.android-x86.org/releases/releasenote-8-1-r6.html, but you can use more fresh Android version. Check it here https://www.android-x86.org/releases
  * After getting iso image with Android distribution install it into your hyper-v environment in Windows. Here you can find useful video with step by step instruction https://www.youtube.com/watch?v=0nlZGvPcEiU
* Install into Android VM applications which you are going to backup. These applications should match with AndroidVmApplicationsForBackupList parameter from configuration file. Login into cloud accounts for your applications on Android VM and make sure that your data was synchonized to the state which you can observe on your regular Android device
* Create your private key using PuttyGen application (you need to have Putty installed on your Windows machine). Place private key into location corresponding to value of AndroidVmSshUserPuttyPrivateKeyFullpathInHostSystem parameter from config
* Configure SSH server on Android VM
  * Install SSH server on Android VM. I used app named "Servers Ultimate" by "Ice Cold Apps" developer https://play.google.com/store/apps/details?id=com.icecoldapps.serversultimate This is paid software. You may find another SSH server for Android. Just keep in mind the goal: being able to connect into your Android VM from host system via SSH. For "Servers Ultimate" you will also have to download "Servers Ultimate Pack E" extension for getting SSH functionality https://play.google.com/store/apps/details?id=com.icecoldapps.serversultimate.packe
  * Setup SSH user - the same as mentioned in AndroidVmSshUsername parameter from config. This will be used for authentication in SSH session
  * Setup passwordless authentication which uses public-private key pair. You will have to copy your public key (corresponding to private key from AndroidVmSshUserPuttyPrivateKeyFullpathInHostSystem config parameter) into Android VM folder where your SSH server will have access to it (in config of your SSH server you have to specify path to allowed public key)
  * Make sure that your SSH server will be automatically started when Android VM is started. E.g. you can add your SSH server application to autostart with help of some Autostart application - e.g. with https://play.google.com/store/apps/details?id=com.autostart
  * As a smoke-test you can try to connect to your VM via SSH (e.g. from putty) using private-public key authentication and AndroidVmSshUsername user. Successful SSH connection is a must for this backup mechanism work
  * Make sure that you know hostkey finger print of Android VM. You will have to provide its value into AndroidVmSshHostKeyFingerprint configuration parameter
* Setup output folder for your backups. Make sure that you can easily access AndroidVmOutputFolderFullpath which mentioned in configuration parameters (you have to create this folder manually). This folder serves as output folder with your backups. And therefore you will have to either map it to Windows host system to access backups or somehow transfer output files into cloud storage directly in Android VM. See description of AndroidVmOutputFolderFullpath configuartion parameters for available options

# Usage
Run backup by executing Start-AndroidBackupEntryPoint.cmd (no arguments required for this cmd. Every configuration is already set in configuration file. See setup section for more details).

If you want to have automatic backup then add task into Windows task scheduler which will regularly run Start-AndroidBackupEntryPoint.cmd (e.g. at certain point of time each day, after login into Windows or after any trigger event of your wish)


# Output
* Output archives located on Android VM in AndroidVmOutputFolderFullpath (path mentioned in configuration parameters. See setup sections for details regarding AndroidVmOutputFolderFullpath)
* Separate archive is created for each application in AndroidVmApplicationsForBackupList (application list mentioned in configuration parameters)
* Format of output archives: yyyyMMdd-HHmmss_AndroidVmApplicationName.cpio (cpio is file type of archive which serves as alternative to zip)
* There is no strict guidance what you can do with output archives. But the following comes to my mind:
    * Those output archives can be used as backups. E.g. if you want to restore your application from backup then do approximately the following (this is risky operation so make sure you understand the technical consequences of what you are doing):
        * Create new Android VM specially for restoring application (you can clone your existing backup VM into new instance)
        * Make sure that your Android VM is not connected to internet (in order to not mess up cloud account data)
        * Install application from Play Market (or from APK-file)
        * Try firstly not to login into your application cloud account
        * Stop application
        * Put unzipped data from your backup archive into /data/data/<application_name> folder
        * Try to run application. If you are lucky then you will see your data here as of backup timestamp
        * If the previous method didn't work then do the following
            * Remove application from new Android VM
            * Install it again
            * Connect VM to internet
            * Login into application with your cloud account. Application will sync its data as of latest state
            * Switch off internet for VM. This is critical to do in order to not mess up your cloud account data
            * Stop application
            * Put unzipped data from your backup archive into /data/data/<application_name> folder
            * Try to run application. Maybe the login will help you here to see your data in application as of certain timestamp
            * If application has export data option then you can create export based on data which is imported from your backup. If application has export option then it probably also has import option. So therefore later you can use your exported data to import back into application to more safely create restore from backup (as restoring directly internal structures from archives and switching on internet leaving everything "as is" is very risky method of restore)
            * After you checked your data as of some timestamp - immediately drop this application so your data folder will be purged. Only after this switch on VM internet. By doing this you will make sure that data for application won't be synchonized with cloud data (this generally depends on application, but in best case only sync will happen with internet, in worst case something unexpected can happen like messing your cloud application data)
    * Also you can use databases from those Android backups for quering your data (typically Android applications store its data in SQLite database format and those db files can be found in archives).
    E.g. you may want to migrate your application data from one Android application into something else. So writing SQL query may be beneficial for getting app data from source structure

# Dependencies
* On host system
  * OS Windows
  * Plink (part of putty - utility to run SSH commands from Windows). Theoretically can be replaced by other SSH software (but code change is needed for changing SSH software)
  * Powershell
  * Hyper-v (virtualization technology)
  * Android installation (iso-image with Android OS distribution)
* On Android VM
  * SSH server for Android
  * Installed applications which you are going to back up


# Troubleshooting
* In case of backup issues the log is the first place to look into. Logs for each backup session are available in c:\Users\<username>\AppData\Local\AndroidBackup\Logs\. Logs are not cleaned up so you can check the execution history

# Notes
* Current version of code is designed for Hyper-V VM only (built into Windows OS virtualization technology), but you can theoretically also use other virtualization technologies (such as VirtualBox or VMware. To use different virtualization technologies code change is required). E.g. if using VirtualBox then you will have to use vagrant to control your VM state (such as start VM, shutdown VM). Theoretically you can also use Bluestacks as your VM, but it will be more complicated because you have to somehow root Bluestacks (compared to VM from iso Android image which is already rooted). Also Bluestacks probably cannot work in background mode. So when your backup is running then you will see Bluestacks window. In hyper-v (or VirtualBox) you won't see VM Window when you control VM from command line. So the backup can run automatically (e.g. after each login/restart of Windows or daily at certain time) and you won't see it (most likey you don't want to see backup window each day. You just want to do backup regularly and quietly)
* Generally designed for Windows machines, but can be also transferred to Linux environment. AFAIK Powershell is also available for Linux (or Powershell part can be rewritten into Python which should work 100% in both Windows and Linux). And you can create Android VM on Linux also (e.g. use VirtualBox instead of Hyper-v)
* Backup application also creates temporary files in c:\Users\<username>\AppData\Local\Temp\AndroidBackup. Generally application cleans up its tmp files itself (each new run application removes tmp files of previous run. So in this folder you can see tmp files only for previous run. It may be beneficial to have those last-run files here for debugging purpose). So no need to manually do cleanup
* This software was tested and used by author so far for backup of the following applications:
  * io.timetrack.timetrackapp
  * ru.zenmoney.androidsub
  * com.google.android.keep
* Generally your Android VM which is used for backup is not intented to be used for other purposes (e.g. for running Android applications on Windows). Having backup on your Android VM can complicate regular usage of VM (e.g. your VM will be started by schedule, applications will be automatically opened to sync data and then VM will be stopped). So if you use Android VM for anything else except backup then create another instance of Android VM which will be used for backup only
* This backup mechanism will work only for applications which store all its cloud data in local Android copy (local copy is /data/data/<application_data>). Example: it is reasonable to expect from "Google Keep" Android application to store all its notes in local Android copy, but it is not feasible to expect "Google Drive" Android applciation to store all its data in local Android copy. It is just unrealistic for Android application to store all your cloud storage files locally in Android (e.g. if you have 100 Gb of cloud storage data). So make sure that you understand the nature of application and feasibility of its backup before including it into backup list. Also not all application will store all cloud data in local copy even if this data is not so huge. Therefore feasibility of this backup depends on whether application can create local copy for all cloud account data you need for backup (otherwise you will create backups based on only that data which was locally available in application folder - e.g. recently cached cloud data because it was used in application, but without any additional data which is not cached in local Android storage)


