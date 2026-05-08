# A ps1 and batch script to check your disk health

# WARNING
## RUNNING RANDOM SCRIPTS YOU FOUND FROM THE INTERNET IS NEVER A GOOD IDEA SO MAKE SURE TO BE ON THE LOOKOUT


# How to Use:
- Download both the disk_check.ps1 and Run_DiskCheck.bat and place both in the same folder.
- then run the Run_DiskCheck.bat


# How it works

## Section 1 - Detecting Disks
The first thing it does is ask Windows to list every physical drive connected to your PC, SSDs, HDDs, anything. It pulls the name, size, media type, and whether Windows considers it healthy. This is just the initial inventory so the rest of the checks know what drives to work with.

## Section 2 - SMART & Reliability Data
SMART is a built-in monitoring system that every modern drive has, it tracks things like how many read/write errors have occurred, how worn out the drive is, how hot it's running, and how many hours it's been powered on. The script reads all of that and flags anything concerning ie. errors above zero, wear level at 90%+, or temperature at 60°C or higher.

## Section 3 - Disk Health Status
A simpler, faster check that just asks Windows directly if it considers each drive healthy and operational. This is separate from SMART. Windows has its own health rating it assigns to drives based on what it knows. If anything comes back as anything other than Healthy and OK, it gets flagged.

## Section 4 - Volume & Partition Check
Shifts focus from the physical drives to the partitions on them. The C:, D: drives etc. that you actually see in File Explorer. It checks whether each one is healthy, how much space is used, and flags it if you're above 80% full as a warning or above 95% as critical, since a nearly full drive can cause all sorts of problems.

## Section 5 - Filesystem Integrity (chkdsk)
Runs the Windows equivalent of a deep scan on each drive's file system, the underlying structure that keeps track of where all your files are stored. If it finds errors it immediately tries a spot fix to repair them on the spot. This is the same thing as running chkdsk manually but done automatically for every drive.

## Section 6 - Event Log Disk Error Scan
Windows logs errors in the background all the time. This section goes through the last 24 hours of those logs and looks specifically for anything mentioning disks, volumes, file systems, bad sectors, or storage errors. If Windows has been quietly noticing problems with your drives, this is where it would show up.

## Section 7 - Memory & Page File
Checks how much RAM your PC is using and flags it if it's above 90%. It also checks the page file(a chunk of your SSD/HDD that Windows uses as overflow when it runs out of RAM). If the page file is over 80% full it means your PC is heavily leaning on the drive to compensate for not having enough memory, which is both slow and puts extra wear on the drive.

## Section 8 - SSD TRIM
TRIM is a maintenance command that SSDs need to healthy. Over time as you delete files, the SSD doesn't actually clear that space until TRIM tells it to. This section runs the optimize command on every drive which triggers TRIM on SSDs and standard defrag logic on HDDs.

## Section 9 - System File Integrity (SFC + DISM)
Runs two of Windows own built-in repair tools back to back. SFC scans all of Windows core system files and checks if any have been corrupted or gone missing, repairing them automatically if it can. If SFC finds damage it can't fix on its own, it then hands off to DISM, a deeper tool that reaches out to Windows own component store to source clean replacement files and restore them. Between the two, most Windows file corruption can be caught and repaired automatically.

## Final Report
Once all nine sections are done, it prints a summary of everything, how many issues were found, what was fixed automatically, and anything it had to skip. The full detailed log is also saved as a timestamped .txt file in the same folder as the script so you have a record of the run.

dont judge me i got all of this from google, reddit, and other tech forums.


