================================================================================
   WINDOWS OPTIMIZER v2.5.0 - Professional Performance & Cleanliness Suite
================================================================================
Senior Windows Performance Optimization & Systems Administration Documentation
Target Operating Systems: Windows 10 (Build 1909+) & Windows 11 (All Builds)
================================================================================

1. OVERVIEW & CORE PHILOSOPHY
--------------------------------------------------------------------------------
Windows Optimizer is an enterprise-grade performance tuning, junk cleanup, and
system responsiveness tool built using a robust Windows Batch (.bat) launcher
integrated with a PowerShell 5.1/7.x execution engine.

Unlike aggressive, reckless "tweakers" that break Windows Update, delete system
components, or butcher networking, Windows Optimizer adheres strictly to the
principles of Senior Windows Systems Engineering:

1. SAFETY FIRST: Never delete personal user files (Documents, Desktop, Downloads,
   Pictures, browser profiles, saved credentials, or app config directories).
2. STABILITY GUARANTEE: In-use and locked files are skipped gracefully without
   errors. Windows Installer, DriverStore, and WinSxS are never deleted manually.
3. PRESERVATION OF CORE SUBSYSTEMS: Audio, networking, printing (unless chosen),
   Bluetooth, Windows Security (Defender, Firewall, SmartScreen), and anti-cheat
   mechanisms (EasyAntiCheat, BattlEye, Vanguard) are strictly protected.
4. FULL REVERSIBILITY: Every registry modification, service adjustment, and
   startup change creates a timestamped JSON backup in the `backups\` directory.
   The built-in Rollback Engine can revert changes at any time.
5. NO FAKE "RAM CLEANING": We do not employ dangerous working-set trimming or
   forced memory purging (e.g. EmptyWorkingSet API calls). Such tricks merely
   force cached memory into the pagefile, causing severe disk thrashing and
   micro-stutters when applications resume.


2. REALISTIC PROCESS COUNT & MEMORY EXPECTATIONS
--------------------------------------------------------------------------------
A common question asked by administrators and power users:
"Why does Windows 10/11 have 200 to 250 running processes compared to Windows 7?"

THE SVCHOST ARCHITECTURE SHIFT:
In Windows 10 Creators Update (Version 1703), Microsoft redesigned the Service
Host model. On any system with more than 3.5 GB of RAM, services that previously
shared a single svchost process are now split into dedicated, isolated svchost
instances.

WHY THIS MATTERS:
- Process count increased from ~80 to 180-250+ by default.
- This was an intentional reliability and security improvement: if one service
  crashes or leaks memory, it does not bring down other critical services.
- A higher process count DOES NOT automatically mean high CPU or RAM consumption.
  An idle svchost process uses virtually 0% CPU and negligible private memory.

TARGET RANGE:
Through disciplined startup management, closing redundant 3rd-party background
helpers, and setting unneeded telemetry and demo services to Manual or Disabled,
Windows Optimizer can safely reduce process count from ~250 down to approximately
140-160 processes on typical installations, without breaking any system features.
Never attempt to force an arbitrary number by killing critical OS components.


3. FILE STRUCTURE & ARCHITECTURE
--------------------------------------------------------------------------------
WindowsOptimizer/
├── WindowsOptimizer.bat     Main launcher, UAC elevation broker & argument handler
├── WindowsOptimizer.ps1     Core PowerShell engine (analysis, cleanup, rollback)
├── README.txt               This comprehensive documentation guide
├── logs/                    Timestamped transaction logs for every execution
├── backups/                 Full state backups (services, registry, startup items)
└── reports/                 System audit and before-and-after optimization reports


4. HOW TO RUN & QUICK START
--------------------------------------------------------------------------------
METHOD 1: INTERACTIVE DASHBOARD (RECOMMENDED)
1. Right-click `WindowsOptimizer.bat` and select "Run as administrator".
2. If launched as a standard user, the launcher will prompt you to elevate via
   User Account Control (UAC), or allow you to continue in user-only mode.
3. The interactive menu provides 12 organized options.

METHOD 2: COMMAND-LINE / AUTOMATION
You can execute specific operations directly from CMD or PowerShell:
  WindowsOptimizer.bat --analyze      (Non-destructive diagnostic assessment)
  WindowsOptimizer.bat --cleanup      (Deep safe junk file cleanup)
  WindowsOptimizer.bat --services     (Windows services optimization)
  WindowsOptimizer.bat --full         (Full safe optimization preset)
  WindowsOptimizer.bat --rollback     (Revert to previous restore point)
  WindowsOptimizer.bat --report       (Generate system performance report)
  WindowsOptimizer.bat --dry-run      (Simulate actions without writing changes)
  WindowsOptimizer.bat --help         (Display parameter reference)


5. DETAILED FEATURE BREAKDOWN
--------------------------------------------------------------------------------

[1] SYSTEM INFORMATION & HEALTH CHECK
    Collects and displays detailed telemetry: OS edition, build number, elevation
    status, CPU cores/threads, real physical RAM in-use vs free, active process
    count, system drive (C:) free space, power plan, and system uptime.

[2] ANALYZE CPU, RAM, DISK, AND RUNNING PROCESSES
    Non-destructive live diagnostic. Displays the Top 10 CPU consumers (by
    cumulative processor time) and Top 10 RAM consumers (by Working Set and
    Private RAM). Categorizes processes into Windows Core vs Third-Party. Scans
    and calculates exact reclaimable disk space across all junk categories.

[3] SAFE DEEP JUNK CLEANUP
    Safely purges verified temporary files:
    - User Temp (%TEMP%) and Windows System Temp (%SystemRoot%\Temp).
    - Windows Error Reporting (WER) archives and application crash dumps.
    - Historical CBS servicing compressed logs and DISM logs.
    - DirectX and GPU Shader Caches (NVIDIA, AMD, Intel, D3D).
    - Delivery Optimization temporary caches.
    - Windows Recycle Bin (only with explicit user confirmation).
    - Windows Component Store cleanup via official DISM command
      (`Dism.exe /Online /Cleanup-Image /StartComponentCleanup`).
    Reports exact bytes and megabytes freed for each category.

[4] STARTUP APPLICATIONS OPTIMIZATION
    Inspects Registry Run keys (HKCU, HKLM, WOW6432Node) and Startup folders.
    Allows toggling startup entries on and off with full backup. Easily disable
    unnecessary 3rd-party updaters (Discord, Spotify, Epic, Adobe, etc.).

[5] BACKGROUND PROCESS MANAGEMENT
    Identifies non-essential 3rd-party user applications running in background.
    Strictly whitelists Windows kernel, shell, security, audio, graphics drivers,
    and anti-cheat processes. Offers graceful window close before terminating.

[6] WINDOWS SERVICES OPTIMIZATION
    Categorized into two transparent groups:
    - Category A (Safe): Telemetry (DiagTrack), WAP Push (dmwappushservice),
      RetailDemo, RemoteRegistry, MapsBroker, and Xbox services set to Manual.
    - Category B (Advanced): Explains hardware-dependent services such as Print
      Spooler, Bluetooth Support, SysMain (SuperFetch), and Windows Search.
      Requires explicit confirmation with clear warnings.
    All original service startup states are saved to JSON before modification.

[7] GAMING OPTIMIZATION PROFILE
    - Verifies and enables Windows Game Mode (prioritizes CPU/GPU scheduling).
    - Inspects Hardware-Accelerated GPU Scheduling (HAGS) status.
    - Identifies non-essential background applications that cause frame pacing
      issues or micro-stutters during gaming sessions.
    - Explains why GPU shader caches should not be cleared constantly.
    - Preserves all anti-cheat, audio, and network capabilities.

[8] OPTIONAL PRIVACY & TELEMETRY OPTIMIZATION
    Kept strictly separate from performance settings:
    - Reduces diagnostic telemetry to Required/Basic level.
    - Disables unique Advertising Identifier.
    - Disables Bing Web Search in Start Menu (makes Start Menu fast & local).
    - Disables activity history timeline publishing.
    - Disables Windows consumer experience suggestions and promotional tiles.

[9] FULL SAFE OPTIMIZATION PIPELINE
    A guided, single-action workflow that captures baseline metrics, runs safe
    junk cleanup, applies safe service tuning, applies privacy adjustments, and
    provides a before-and-after comparison of process count, RAM, and disk freed.

[10] RESTORE PREVIOUS CHANGES (ROLLBACK ENGINE)
    Enumerates all previous backup sessions stored in `backups\`. Allows instant
    restoration of original service startup configurations, registry values,
    and startup entries.

[11] GENERATE OPTIMIZATION REPORT
    Generates a comprehensive Markdown report in the `reports\` folder detailing
    system hardware specs, health metrics, disk space freed, and modifications.

[12] EXIT


6. TESTING & VALIDATION PROCEDURE
--------------------------------------------------------------------------------
To test and verify the optimizer safely on any system:

STEP 1: DRY-RUN SIMULATION
Run `WindowsOptimizer.bat --dry-run` or execute Option 2 (Analyze).
Verify that all scans complete cleanly and report estimated space without
altering any files or registry settings.

STEP 2: RUN DEEP JUNK CLEANUP
Execute Option 3. Check the reported disk space freed. Verify that your personal
files (Documents, Desktop, Downloads, browser history/logins) remain intact.

STEP 3: RUN FULL SAFE OPTIMIZATION
Execute Option 9. Observe the baseline metrics, the live progress, and the
final comparison showing reduced process count and reclaimed disk space.

STEP 4: TEST ROLLBACK ENGINE
Execute Option 10. Select the newly created backup point and confirm rollback.
Verify that all services and registry entries return to their original values.


7. SAFETY WHITELISTS REFERENCE
--------------------------------------------------------------------------------
PROTECTED PROCESSES (Never terminated by the optimizer):
  system, idle, registry, smss, csrss, wininit, services, lsass, winlogon,
  svchost, fontdrvhost, dwm, explorer, sihost, taskhostw, runtimebroker,
  searchhost, startmenuexperiencehost, shellexperiencehost, conhost, cmd,
  powershell, pwsh, spoolsv, audiodg, ctfmon, securityhealthservice,
  securityhealthsystray, msmpeng, nissrv, smartscreen, memory compression,
  nvcontainer, nvsphelper64, radeonsoftware, amdrsserv, igfxem, realtek*,
  easyanticheat, beservice, bedaisy, vgk, vgc.

PROTECTED SERVICES (Never disabled or modified):
  RpcSs, RpcEptMapper, DcomLaunch, PlugPlay, SamSs, LSM, EventLog, Schedule,
  ProfSvc, CryptSvc, StateRepository, CoreMessagingRegistrar, Power,
  WinDefend, WdNisSvc, SecurityHealthService, wscsvc, Sense,
  Dhcp, Dnscache, LanmanWorkstation, LanmanServer, NlaSvc, netprofm, WlanSvc,
  AudioSrv, AudioEndpointBuilder, wuauserv, bits, dosvc, TrustedInstaller.


8. TROUBLESHOOTING & SUPPORT
--------------------------------------------------------------------------------
Q: "The script says Administrator elevation is recommended."
A: Right-click `WindowsOptimizer.bat` and choose "Run as administrator". While
   analysis and user junk cleanup work in standard user mode, modifying system
   services and system temporary directories requires elevation.

Q: "How do I reverse changes if an application acts differently?"
A: Simply run `WindowsOptimizer.bat`, select Option 10 ("Restore Previous Changes"),
   and select the backup timestamp from when you ran the optimization.

Q: "Why didn't my process count drop to 100?"
A: Modern Windows 10/11 isolates services across many svchost processes for
   stability and memory protection. A running count of 140-160 with 0-1% idle CPU
   is optimal and healthy. Forcing lower counts by killing core services causes
   system instability and data loss.

================================================================================
Developed with precision by a Senior Windows Performance Optimization Engineer.
================================================================================
