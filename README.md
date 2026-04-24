# where-we-left-off.sh

A resilient Linux utility for transferring files off of damaged drives.  The key is traversing their directory trees in a way that can safely resume after interruption (e.g., drive disconnects, overheating, crashes). It combines aspects of `du`, `rsync`, `diff`, and `tree` into a single interruptible workflow.

Progress is continuously saved, allowing you to pick up exactly where you left off.

## Features

- Resume traversal after interruption using a persistent state file

- Multiple operation modes: transfer files (copy), size calculation, diff paths, or print paths

- Handles large or unstable storage (external drives, network mounts)

- Adjustable delay between operations to reduce system stress and heat

- Tracks total files processed and cumulative size

## Installation

Place the script somewhere in your PATH and make it executable:

```bash
chmod +x where-we-left-off.sh
mv where-we-left-off.sh ~/.local/bin/
```

## Usage

```bash
where-we-left-off.sh [options] source_directory > [destination_directory]
```

## Options

- `-c, --copy`
  Copy files from source to destination using `rsync`

- `-z, --size`
  Calculate total size only (default mode)

- `-d, --diff`
  Show files that differ between source and destination (by size or mtime)

- `-p, --print`
  Print each visited file/directory

- `-s, --status`
  Show last saved progress (last processed file, count, total size)

- `--clear`
  Clear saved progress

- `-l, --leftoff <path>`
  Override saved position and resume after this path

- `-r, --rest <seconds>`
  Delay between processing items (default: 0.01)

- `-h, --help`
  Show help message

## Examples

Resume or begin a copy operation
```bash
where-we-left-off.sh -c /mnt/source /mnt/backup
```
Resume or begin a size calculation
```bash
where-we-left-off.sh /mnt/drive
```
Check progress (where we left off)
```bash
where-we-left-off.sh --status
```
Compare two directories
```bash
where-we-left-off.sh -d /mnt/source /mnt/backup
```
Slow down traversal (for fragile drives)
```bash
where-we-left-off.sh -r 0.1 /mnt/drive
```

## How It Works
- Progress is saved to:
```text
~/.where-we-left-off
```

- Each processed item updates:
    - Last visited path
    - Total files processed
    - Total bytes accumulated

If the script exits unexpectedly, rerunning it continues from the last saved position.

Completed runs are archived to:
```text
~/.where-we-left-off.archive
```

## Limitations

- Slow, but that's fine for data recovery

- Files are assumed identical if size and modification time match

- Known print bug with Chinese filenames (characters wider than one column)

## Tip

- If you've reached the point of needing this utility, make sure you try the problematic drive in Windows first.
