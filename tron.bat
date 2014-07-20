:: Purpose:       Runs a series of cleaners and anti-virus engines to clean up/disinfect a PC
::                  Kevin Flynn:  "Who's that guy?"
::                  Program:      "That's Tron. He fights for the Users."
:: Requirements:  1. Administrator access
::                2. Safe mode is strongly recommended
:: Author:        vocatus on reddit.com/r/sysadmin ( vocatus.gate@gmail.com ) // PGP key ID: 0x82A211A2
:: Version:       1.7  + tron.bat:          Added check for Administrator rights. Thanks to reddit.com/user/apcomputerworks
::                     + stage_2_disinfect: Added Emsisoft Commandline Scanner. "smart" scan + NTFS alternate data streams scan. Uses Direct Disk Access mode. Deletes detected malware immediately (/delete flag)
::                1.6  + stage_2_disinfect: Added System File Checker scan to repair broken Windows core files. Skipped on XP and Server 2003 since
::                                          these require an original install disk to function. Thanks to reddit.com/user/cyr4n0
::                     + stage_0_prep:      Added code to detect and repair broken WMI configurations
::                1.5  + tron.bat:          Added "-auto" flag to support silent/scripted execution. Run the script and pass "-auto"
::                                          as the first argument and Tron will run silently while still using all settings configured
::                                          in the VARIABLES section
::                     * tron.bat:          Set power mode to "Always On/High Performance" at start of script, then reset power settings to Windows defaults when finished
::                     * tron.bat:          General cleanup of many conditional tests; should slightly speed script up
::                     * stage_4_patch:     Remove all existing JRE versions prior to installing latest JRE
::                1.4  + tron.bat:          Added SKIP_DEFRAG variable to force defrag to always skip
::                     * tron.bat:          Improved SSD detection. Thanks to reddit.com/user/bdm800
::                     * tron.bat:          Cleaned up welcome screen and various comments
::                     * tron.bat:          Reduced time spent waiting for rkill from 110 seconds to 90 seconds
::                     * stage_2_disinfect: Switched Sophos and Vipre to log to console instead of log file.
::                                          This way you can see which file they're on, and prevents people from thinking
::                                          the scanner is stalled.
::                1.3  * stage_4_patch:     Updated links for Adobe Flash and Notepad++ to reflect new versions
::                1.2  + stage_5_optimize:  Added detection of SSD drives. If drive is detected, post-run defrag is skipped
::                                          Thanks to reddit.com/user/you_drown_now for help with this function.
::                     * stage_3_de-bloat:  Improved logic, logging, and robustness for WMIC removal section
::                     * tron.bat:          Improved overall logging, appearance and commenting. Added clarification screens for
::                                          various Safe Mode states
::                     / Intro screen:      Adjusted runtime estimates based on user feedback
::                     / tron.bat:          Disabled post-run auto-reboot by default. Change "REBOOT_DELAY" variable if you wish to auto-reboot
::                     - tron.bat:          Removed section asking user if we want to do a post-run defrag (replaced by auto-detect)
::                     - stage_1_tempclean: Removed TempFileCleanup job (ccleaner and bleachbit cover this requirement)
::                     - stage_4_patch:     Removed /r flag on wuauclt command
::                1.1  * tron.bat:          Various comment, log and syntax cleanup
::                     + tron.bat:          Added section to ask if we want to do a post-run defrag, and skip the defrag
::                                          if the user says no
::                     * tron.bat:          Removed hard requirement to run in safe mode and added code to detect various Safe Mode states
::                     * stage_3_de-bloat:  Converted section to read from a text list located in
::                                          resource\stage_3_de-bloat\programs_to_target.txt
::                     + stage_3_de-bloat:  Added additional programs to find and remove
::                     + stage_3_de-bloat:  Added line to remove Adobe Shockwave (not in wide use anymore)
::                     - stage_4_patch:     Removed installation of Adobe Shockwave
::                1.0    Initial write

:: Usage:         Run this script as an Administrator and let it reboot when finished.



:: TODO:   log a2cmd run?     /l=[], /log=[filepath]      Save a logfile in UNICODE format



:::::::::::::::::::::
:: Prep and Checks :: -- Don't change anything in this section
::::::::::::::::::::: -- Set the variables in the "variables" section below
@echo off && cls
echo. && echo  Loading... && echo.
SETLOCAL
set VERSION=1.7
set UPDATED=2014-07-xx
title TRON v%VERSION% (%UPDATED%)
:: Get the date into a format we can use
if "%DATE:~-5,1%"=="/" (set CUR_DATE=%DATE:~-4%-%DATE:~4,2%-%DATE:~7,2%) else (set CUR_DATE=%DATE%)
:: Get in the correct drive. This is sometimes needed when running from a thumb drive
%~d0 2>NUL
:: Get in the correct drive. This is useful if we start from a network share; convert CWD to a drive letter
pushd %~dp0 2>NUL

:: Detect if we're on an XP/2k3-series kernel
:: This is used to determine which powercfg.exe commands to run in the Prep section
set WIN_VER=undetected
ver | find /i "Version 5." >NUL
if %ERRORLEVEL%==0 set WIN_VER=xp2k3

:: Detect Solid State hard drives (determines if post-run defrag executes or not)
REM pushd resources\stage_5_optimize\defrag
REM set SSD_DETECTED=no
REM smartctl -a /dev/sda | find /i "Solid State" >NUL
REM if %ERRORLEVEL%==0 set SSD_DETECTED=yes
REM smartctl -a /dev/sdb | find /i "Solid State" >NUL
REM if %ERRORLEVEL%==0 set SSD_DETECTED=yes
REM smartctl -a /dev/sda | find /i "SSD" >NUL
REM if %ERRORLEVEL%==0 set SSD_DETECTED=yes
REM smartctl -a /dev/sdb | find /i "SSD" >NUL
REM if %ERRORLEVEL%==0 set SSD_DETECTED=yes
REM popd

:: Detect Solid State hard drives (determines if post-run defrag executes or not)
:: Thanks to /u/Suddenly_Engineer and /u/Aberu for this solution
pushd resources\stage_5_optimize\defrag
set SSD_DETECTED=no
for /f "tokens=1" %%i in ('smartctl --scan') do smartctl %%i -a | find /i "Solid State" >NUL
if %ERRORLEVEL%==0 set SSD_DETECTED=yes
for /f "tokens=1" %%i in ('smartctl --scan') do smartctl %%i -a | find /i "SSD" >NUL
if %ERRORLEVEL%==0 set SSD_DETECTED=yes
popd


:: Detect Safe Mode
set SAFE_MODE=no
if /i "%SAFEBOOT_OPTION%"=="MINIMAL" set SAFE_MODE=yes
if /i "%SAFEBOOT_OPTION%"=="NETWORK" set SAFE_MODE=yes


:::::::::::::::
:: VARIABLES :: -- Set these to your desired values
:::::::::::::::
:: Rules for variables:
::  * NO quotes!                       (bad:  "c:\directory\path"       )
::  * NO trailing slashes on the path! (bad:   c:\directory\            )
::  * Spaces are okay                  (okay:  c:\my folder\with spaces )
::  * Network paths are okay           (okay:  \\server\share name      )
::                                     (       \\172.16.1.5\share name  )

:: Log settings
set LOGPATH=%SystemDrive%\Logs
set LOGFILE=tron.log

:: Post-run delay (in seconds) before rebooting. Set to 0 to disable auto-reboot.
set REBOOT_DELAY=0

:: Set to anything but "no" in order to skip defrag regardless whether the system drive is an SSD or not.
:: Leave as "no" to let the script auto-detect SSDs
set SKIP_DEFRAG=no


:: -------------------------- Don't edit anything below this line -------------------------- ::


:: Check for autorun
if "%1"=="-auto" goto execute_jobs

:::::::::::::::::::::::
:: LOG FILE HANDLING ::
:::::::::::::::::::::::
if not exist %LOGPATH% mkdir %LOGPATH%
if not exist %LOGPATH%\%LOGFILE% echo. > %LOGPATH%\%LOGFILE%

::::::::::::::::::::
:: WELCOME SCREEN ::
::::::::::::::::::::
:welcome_screen
cls
echo  *****************  TRON v%VERSION% (%UPDATED%)  ******************
echo  * Script to automate a series of cleanup/disinfect tools.   *
echo  * Author: vocatus on reddit.com/r/sysadmin                  *
echo  *                                                           *
echo  * Stage:         Tools:                                     *
echo  * --------------------------------------------------------- *
echo  *  0 Prep:       rkill, WMI repair                          *
echo  *  1 TempClean:  BleachBit, CCleaner                        *
echo  *  2 Disinfect:  Vipre, Sophos, MBAM                        *
echo  *  3 De-bloat:   Remove OEM bloatware apps                  *
echo  *  4 Patch:      Update 7-Zip/Java/Flash/Windows            *
echo  *  5 Optimize:   Defrag %SystemDrive% (non-SSD only)                   *
echo  *                                                           *
echo  * The \resources folder contains additional tools which may *
echo  * be run manually if necessary.                             *
echo  *************************************************************
echo.
:: This is so ugly it makes me cry
echo  Current settings (edit script to change):
echo     Log location:            %LOGPATH%\%LOGFILE%
if not "%REBOOT_DELAY%"=="0" echo     Post-clean reboot delay: %REBOOT_DELAY% seconds
if "%REBOOT_DELAY%"=="0" echo     Post-clean reboot delay: disabled
if "%SSD_DETECTED%"=="yes" echo     SSD detected?            %SSD_DETECTED% (stage_5 skipped)
if "%SSD_DETECTED%"=="no" echo     SSD detected?            %SSD_DETECTED%
if "%SAFEBOOT_OPTION%"=="MINIMAL" echo     Safe mode?               %SAFE_MODE%, without Networking
if "%SAFEBOOT_OPTION%"=="NETWORK" echo     Safe mode?               %SAFE_MODE%, with Networking (ideal)
if not "%SAFE_MODE%"=="yes" echo     Safe mode?               %SAFE_MODE% (not ideal)
if not "%SKIP_DEFRAG%"=="no" (
	echo   ! SKIP_DEFRAG set; skipping stage_5_optimize ^(defrag^)
	echo     Runtime estimate:        3-5 hours
	goto welcome_screen_trailer
	)
if "%SSD_DETECTED%"=="yes" echo     Runtime estimate:        3-5 hours
if not "%SSD_DETECTED%"=="yes" echo     Runtime estimate:        5-7 hours
echo.
:welcome_screen_trailer
pause

::::::::::::::::::::::::
:: ADMIN RIGHTS CHECK ::
::::::::::::::::::::::::
set ADMINDIR=%WINDIR%\System32\Test_%RANDOM%
mkdir "%ADMINDIR%" 2>NUL
if not "%ERRORLEVEL%"=="" (
		color 0c
		cls
		echo.
		echo  ERROR
		echo.
		echo  Tron is not running as an Administrator. Tron MUST
		echo  be run with full Administrator rights to function.
        echo  Run from an elevated command-prompt, or right-click
		echo  and "Run as Administrator."
		echo.
		pause
		exit /b 1
	) else (
		rmdir /s /q "%ADMINDIR%"
	)

:::::::::::::::::::::
:: SAFE MODE CHECK ::
:::::::::::::::::::::
:: Test if we're in safe mode
if not "%SAFE_MODE%"=="yes" (
		color 0c
		cls
		echo.
		echo  WARNING
		echo.
		echo  The system is not in safe mode. Tron functions best
		echo  in "Safe Mode with Networking" in order to download
        echo  Windows and anti-virus updates.
		echo.
		echo  Tron will still function, but rebooting to "Safe Mode
		echo  with Networking" is STRONGLY recommended.
		echo.
		pause
		cls
		)

:: Test if we have network support
if /i  "%SAFEBOOT_OPTION%"=="MINIMAL" (
		color 0e
		cls
		echo.
		echo  NOTE
		echo.
		echo  The system is in Safe Mode without Network support.
		echo  Tron functions best in "Safe Mode with Networking" in
        echo  order to download Windows and anti-virus updates.
		echo.
		echo  Tron will still function, but rebooting to "Safe Mode
		echo  with Networking" is recommended.
		echo.
		pause
		cls
		)
		
::::::::::::::::::
:: EXECUTE JOBS ::
::::::::::::::::::
:execute_jobs
color 0f
title TRON v%VERSION% [stage_0_prep]
:: Create the log header for this job
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------
echo  %CUR_DATE% %TIME%  TRON v%VERSION% (%UPDATED%), %WIN_VER% %PROCESSOR_ARCHITECTURE% detected>> %LOGPATH%\%LOGFILE%
echo  %CUR_DATE% %TIME%  TRON v%VERSION% (%UPDATED%), %WIN_VER% %PROCESSOR_ARCHITECTURE% detected
echo                          Executing as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%>> %LOGPATH%\%LOGFILE%
echo                          Executing as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------


:::::::::::::::::::
:: STAGE 0: PREP ::
:::::::::::::::::::
:stage_0_prep
pushd resources\stage_0_prep
echo %CUR_DATE% %TIME%   Launching stage_0_prep jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_0_prep jobs...

:: JOB: rkill (kills running malware processes)
echo %CUR_DATE% %TIME%   Launching job 'rkill'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'rkill'...
echo %CUR_DATE% %TIME%   Pinging localhost while waiting for rkill to finish...
pushd rkill
if '%PROCESSOR_ARCHITECTURE%'=='AMD64' start /MIN "" "rkill64.exe"
if '%PROCESSOR_ARCHITECTURE%'=='x86' start /MIN "" "rkill.exe"
ping localhost -n 90 >NUL
TASKKILL /F /IM rkill64.exe /T 2>NUL
TASKKILL /F /IM rkill.exe /T 2>NUL
TASKKILL /F /IM notepad.exe /T 2>NUL
:: Dump the rkill log into the tron log
type %USERPROFILE%\Desktop\rkill.txt>> %LOGPATH%\tron.log
del %USERPROFILE%\Desktop\rkill.txt
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Disable sleep mode
echo %CUR_DATE% %TIME%   Disabling Sleep mode...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Disabling Sleep mode...
pushd disable_sleep
:: Check for Windows XP and run the appropriate powercfg command
if "%WIN_VER%"=="xp2k3" (powercfg /SETACTIVE "Always On") else (powercfg /SETACTIVE 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c)
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Check and Repair WMI if it's broken
echo %CUR_DATE% %TIME%   Checking WMI...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Checking WMI...
pushd wmi_repair

:: Do a quick check to make sure WMI is working, and if not, repair it
wmic timezone >NUL
if not %ERRORLEVEL%==0 (
    echo %CUR_DATE% %TIME% ! WMI appears to be broken. Running WMI repair. This might take a minute, please be patient...>> "%LOGPATH%\%LOGFILE%"
    echo %CUR_DATE% %TIME% ! WMI appears to be broken. Running WMI repair. This might take a minute, please be patient...
    net stop winmgmt
    pushd %WINDIR%\system32\wbem
    for %%i in (*.dll) do RegSvr32 -s %%i
    :: Kill this random window that pops up
    tskill wbemtest /a 2>NUL
    scrcons.exe /RegServer
    unsecapp.exe /RegServer
    start "" wbemtest.exe /RegServer
    tskill wbemtest /a 2>NUL
    tskill wbemtest /a 2>NUL
    :: winmgmt.exe /resetrepository       -- optional; forces full rebuild instead of a repair like the line below this
	winmgmt.exe /salvagerepository /resyncperf
    wmiadap.exe /RegServer
    wmiapsrv.exe /RegServer
    wmiprvse.exe /RegServer
    net start winmgmt
	)

popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

popd
echo %CUR_DATE% %TIME%   Completed stage_0_prep jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_0_prep jobs.


::::::::::::::::::::::::
:: STAGE 1: TEMPCLEAN ::
::::::::::::::::::::::::
:stage_1_tempclean
title TRON v%VERSION% [stage_1_tempclean]
pushd resources\stage_1_tempclean
echo %CUR_DATE% %TIME%   Launching stage_1_tempclean jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_1_tempclean jobs...

:: JOB: CCLeaner
echo %CUR_DATE% %TIME%   Launching job 'CCleaner'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'CCleaner'...
pushd ccleaner
ccleaner.exe /auto
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: BleachBit
echo %CUR_DATE% %TIME%   Launching job 'BleachBit'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'BleachBit'...
pushd bleachbit
bleachbit_console.exe --preset -c>> "%LOGPATH%\%LOGFILE%" 2>NUL
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

popd
echo %CUR_DATE% %TIME%   Completed stage_1_tempclean jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_1_tempclean jobs.


::::::::::::::::::::::::
:: STAGE 2: Disinfect ::
::::::::::::::::::::::::
:stage_2_disinfect
title TRON v%VERSION% [stage_2_disinfect]
pushd resources\stage_2_disinfect
echo %CUR_DATE% %TIME%   Launching stage_2_disinfect jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_2_disinfect jobs...

:: JOB: Emsisoft Commandline Scanner (a2cmd)
echo %CUR_DATE% %TIME%   Launching job 'Emsisoft Commandline Scanner'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Emsisoft Commandline Scanner'...
echo %CUR_DATE% %TIME%   Logging to console instead of logfile for this job...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Logging to console instead of logfile for this job...
pushd a2cmd
a2cmd.exe /update
a2cmd.exe /smart /dda /ntfs /delete
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: VIPRE Rescue
echo %CUR_DATE% %TIME%   Launching job 'Vipre rescue scanner' (takes a long time)...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Vipre rescue scanner' (takes a long time)...
echo %CUR_DATE% %TIME%   Logging to console instead of logfile for this job...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Logging to console instead of logfile for this job...
pushd vipre_rescue
VipreRescueScanner.exe
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Sophos Virus Remover
echo %CUR_DATE% %TIME%   Launching job 'Sophos Virus Removal Tool' (takes a long time)...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Sophos Virus Removal Tool' (takes a long time)...
echo %CUR_DATE% %TIME%   Logging to console instead of logfile for this job...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Logging to console instead of logfile for this job...
pushd sophos_virus_remover
svrtcli.exe -yes
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: MBAM (MalwareBytes Anti-Malware)
echo %CUR_DATE% %TIME%   Launching job 'Malwarebytes Anti-Malware', continuing other jobs..."%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Malwarebytes Anti-Malware', continuing other jobs...
pushd mbam

:: Install & remove the desktop icon
"Malwarebytes Anti-Malware v2.0.2.1012.exe" /verysilent
if exist "%PUBLIC%\Desktop\Malwarebytes Anti-Malware.lnk" del "%PUBLIC%\Desktop\Malwarebytes Anti-Malware.lnk"
if exist "%USERPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk" del "%USERPROFILE%\Desktop\Malwarebytes Anti-Malware.lnk"

:: Scan
pushd "%ProgramFiles(x86)%\Malwarebytes Anti-Malware"
start "" "mbam.exe"
popd


popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: System File Checker scan
echo %CUR_DATE% %TIME%   Launching job 'System File Checker'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'System File Checker'...
pushd sfc
:: Basically this says "If OS is NOT XP or 2003, then go ahead and run system file checker
if not "%WIN_VER%"=="xp2k3" sfc /scannow
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.



popd
echo %CUR_DATE% %TIME%   Completed stage_2_disinfect jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_2_disinfect jobs.


:::::::::::::::::::::::
:: STAGE 3: De-Bloat ::
:::::::::::::::::::::::
:stage_3_de-bloat
title TRON v%VERSION% [stage_3_de-bloat]
pushd resources\stage_3_de-bloat
echo %CUR_DATE% %TIME%   Launching stage_3_de-bloat jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_3_de-bloat jobs...

:: JOB: Remove crapware programs
echo %CUR_DATE% %TIME%   Searching for and removing common crapware programs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Searching for and removing common crapware programs...
echo %CUR_DATE% %TIME%   Customize list here: \resources\stage_3_de-bloat\programs_to_target.txt>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Customize list here: \resources\stage_3_de-bloat\programs_to_target.txt
:: This searches through the list of programs in "programs_to_target.txt" file and uninstalls them one-by-one
FOR /F "tokens=*" %%i in (programs_to_target.txt) DO echo  %%i && echo  %%i...>> "%LOGPATH%\%LOGFILE%" && wmic product where "name like '%%i'" uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

popd
echo %CUR_DATE% %TIME%   Completed stage_3_de-bloat jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_3_de-bloat jobs.


::::::::::::::::::::::
:: STAGE 4: Patches ::
::::::::::::::::::::::
:stage_4_patch
title TRON v%VERSION% [stage_4_patch]
pushd resources\stage_4_patch
echo %CUR_DATE% %TIME%   Launching stage_4_patch jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_4_patch jobs...

:: Prep task: enable MSI installer in Safe Mode
start "" "enable_msi_installer\SafeMSI.exe"
ping localhost -n 2 >NUL
taskkill /im SafeMSI.exe /f /t

:: JOB: 7-Zip
echo %CUR_DATE% %TIME%   Launching job '7-Zip'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job '7-Zip'...

:: Check if we're on 32-bit Windows and run the appropriate architecture installer
if '%PROCESSOR_ARCHITECTURE%'=='x86' (
	pushd 7-zip\v9.20\x86
	setlocal
	call "7-Zip v9.20 x86.bat"
	endlocal
	popd
) else (
	pushd 7-zip\v9.20\x64
	setlocal
	call "7-Zip v9.20 x64.bat"
	endlocal
	popd
	)

echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Adobe Flash Player
echo %CUR_DATE% %TIME%   Launching job 'Update Adobe Flash Player'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Update Adobe Flash Player'...
pushd "adobe\flash_player\v14.0.0.145\firefox"
setlocal
call "Adobe Flash Player (Firefox).bat"
endlocal
popd
pushd "adobe\flash_player\v14.0.0.125\internet explorer"
setlocal
call "Adobe Flash Player (IE).bat"
endlocal
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Adobe Reader
echo %CUR_DATE% %TIME%   Launching job 'Update Adobe Reader'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Update Adobe Reader'...
pushd adobe\reader\v11.0.07\x86
setlocal
call "Adobe Reader.bat"
endlocal
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Remove outdated JRE runtimes (security risk)
echo %CUR_DATE% %TIME%   Checking and removing outdated JRE installations...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Checking and removing outdated JRE installations...
:: Okay, so all JRE runtimes (series 4-8) use product GUIDs, with certain numbers that increment with each new update (e.g. Update 25)
:: This makes it easy to catch ALL of them through liberal use of WMI wildcards ("_" is single character, "%" is any number of characters)
:: Additionally, JRE 6 introduced 64-bit runtimes, so in addition to the two-digit Update XX revision number, we also check for the architecture 
:: type, which always equals '32' or '64'. The first wildcard is the architecture, the second is the revision/update number.

:: JRE 8
:: we can skip JRE 8 because the JRE 8 updater automatically removes older versions, so no need to check twice

:: JRE 7
echo %CUR_DATE% %TIME%   JRE 7...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   JRE 7...
%WMIC% product where "IdentifyingNumber like '{26A24AE4-039D-4CA4-87B4-2F8__170__FF}'" call uninstall /nointeractive >> "%LOGPATH%\%LOGFILE%"

:: JRE 6
echo %CUR_DATE% %TIME%   JRE 6...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   JRE 6...
:: 1st line is for updates 23-xx, after 64-bit runtimes were introduced.
:: 2nd line is for updates 1-22, before Oracle released 64-bit JRE 6 runtimes
%WMIC% product where "IdentifyingNumber like '{26A24AE4-039D-4CA4-87B4-2F8__160__FF}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"
%WMIC% product where "IdentifyingNumber like '{3248F0A8-6813-11D6-A77B-00B0D0160__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

:: JRE 5
echo %CUR_DATE% %TIME%   JRE 5...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   JRE 5...
%WMIC% product where "IdentifyingNumber like '{3248F0A8-6813-11D6-A77B-00B0D0150__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

:: JRE 4
echo %CUR_DATE% %TIME%   JRE 4...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   JRE 4...
%WMIC% product where "IdentifyingNumber like '{7148F0A8-6813-11D6-A77B-00B0D0142__0}'" call uninstall /nointeractive>> "%LOGPATH%\%LOGFILE%"

echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Java Runtime 8
echo %CUR_DATE% %TIME%   Launching job 'Update Java Runtime Environment'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Update Java Runtime Environment'...

:: Check if we're on 32-bit Windows and run the appropriate architecture installer
if '%PROCESSOR_ARCHITECTURE%'=='x86' (
	echo %CUR_DATE% %TIME%   x86 architecture detected, installing x86 version...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%   x86 architecture detected, installing x86 version...
	pushd java\jre\8\u5\x86
	setlocal
	call "jre-8u5-windows-x86.bat"
	endlocal
	popd
) else (
	echo %CUR_DATE% %TIME%   x64 architecture detected, installing x64 version...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%   x64 architecture detected, installing x64 version...
	pushd java\jre\8\u5\x64
	setlocal
	call "jre-8u5-windows-x64.bat"
	endlocal
	popd
	)

echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Notepad++
echo %CUR_DATE% %TIME%   Launching job 'Update Notepad++'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Update Notepad++'...
pushd notepad++\v6.6.7
setlocal
call "npp.Installer.bat"
endlocal
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

:: JOB: Windows updates
echo %CUR_DATE% %TIME%   Launching job 'Install Windows updates'...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching job 'Install Windows updates'...
pushd windows_updates
wuauclt /detectnow /updatenow
popd
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

popd
echo %CUR_DATE% %TIME%   Completed stage_4_patch jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_4_patch jobs.


:::::::::::::::::::::::
:: STAGE 5: Optimize ::
:::::::::::::::::::::::
:stage_5_optimize
title TRON v%VERSION% [stage_5_optimize]
pushd resources\stage_5_optimize
echo %CUR_DATE% %TIME%   Launching stage_5_optimize jobs...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Launching stage_5_optimize jobs...

:: Check if we are supposed to run a defrag before doing this section
if "%SKIP_DEFRAG%"=="yes" (
	echo %CUR_DATE% %TIME%   SKIP_DEFRAG set to "yes". Skipping job.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%   SKIP_DEFRAG set to "yes". Skipping job.
	popd
	goto :wrap-up
	)

:: Check if we are supposed to run a defrag before doing this section
if "%SSD_DETECTED%"=="yes" (
	echo %CUR_DATE% %TIME%   Solid State hard drive detected. Skipping job 'Defrag %SystemDrive%'.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%   Solid State hard drive detected. Skipping job 'Defrag %SystemDrive%'.
	popd
	goto :wrap-up
	)

:: JOB: Defrag the system drive
if "%SSD_DETECTED%"=="no" (
	echo %CUR_DATE% %TIME%   Launching job 'Defrag %SystemDrive%'...>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%   Launching job 'Defrag %SystemDrive%'...
	pushd defrag
	df.exe %SystemDrive%
	popd
	echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME%   Done.
	)

popd
echo %CUR_DATE% %TIME%   Completed stage_5_optimize jobs.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Completed stage_5_optimize jobs.


:::::::::::::
:: Wrap-up ::
:::::::::::::
:wrap-up
echo %CUR_DATE% %TIME%   Wrapping up...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Wrapping up...

echo %CUR_DATE% %TIME%   Resetting power settings to their defaults...>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Resetting power settings to their defaults...
:: Check for XP and run the appropriate version of the command
if "%WIN_VER%"=="xp2k3" (powercfg /RestoreDefaultPolicies) else (powercfg -restoredefaultschemes)
echo %CUR_DATE% %TIME%   Done.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Done.

title TRON v%VERSION% [DONE]

echo %CUR_DATE% %TIME%   DONE. Use the tools in resources\stage_6_manual_tools if further cleaning is required.>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   DONE. Use the tools in resources\stage_6_manual_tools if further cleaning is required.
echo %CUR_DATE% %TIME%   Logfile is located at %LOGPATH%\%LOGFILE%>> "%LOGPATH%\%LOGFILE%"
echo %CUR_DATE% %TIME%   Logfile is located at %LOGPATH%\%LOGFILE%

if "%REBOOT_DELAY%"=="0" (
	echo %CUR_DATE% %TIME% ! Auto-reboot disabled. Recommend rebooting as soon as possible.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME% ! Auto-reboot disabled. Recommend rebooting as soon as possible.
) else (
	echo %CUR_DATE% %TIME% ! Rebooting in %REBOOT_DELAY% seconds.>> "%LOGPATH%\%LOGFILE%"
	echo %CUR_DATE% %TIME% ! Rebooting in %REBOOT_DELAY% seconds.
	)

:: Create the log trailer for this job
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------
echo  %CUR_DATE% %TIME%  TRON v%VERSION% (%UPDATED%) complete>> %LOGPATH%\%LOGFILE%
echo  %CUR_DATE% %TIME%  TRON v%VERSION% (%UPDATED%) complete
echo                          Executed as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%>> %LOGPATH%\%LOGFILE%
echo                          Executed as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%
echo ------------------------------------------------------------------------------->> %LOGPATH%\%LOGFILE%
echo -------------------------------------------------------------------------------

if not "%REBOOT_DELAY%"=="0" shutdown /r /f /t %REBOOT_DELAY% /c "Rebooting in %REBOOT_DELAY% seconds to finish cleanup."
pause