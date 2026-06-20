# spd-say


## Actual Code Documentation and Revision History

---

## Revision History

| Version |    Date | Description                                                                                          |
| ------- | ------: | ---------------------------------------------------------------------------------------------------- |
| 1.0     | Initial | Created basic PowerShell text-to-speech test using `spd-say` on Ubuntu/Linux.                        |
| 1.1     | Updated | Added PDF text extraction using `pdftotext`.                                                         |
| 1.2     | Updated | Added page-specific reading using `-f` and `-l` options in `pdftotext`.                              |
| 1.3     | Updated | Added OCR support using `ocrmypdf` and `tesseract-ocr`.                                              |
| 1.4     | Updated | Added menu-driven interface.                                                                         |
| 1.5     | Updated | Added automatic PDF listing from the script folder when no path is entered.                          |
| 1.6     | Updated | Added ability to stop speech while audio is playing using `S`, `Q`, or `Esc`.                        |
| 1.7     | Updated | Changed search behavior to search the whole PDF by default instead of asking for a page range.       |
| 1.8     | Updated | Added paged search output so the screen pauses when search results fill the terminal.                |
| 1.9     | Current | Added search result reader so the user can read a matching line, context, full page, or all matches. |

---

# Code Documentation

## Script Parameter

```powershell
param(
    [string]$PdfPath
)
```

### Purpose

The script accepts an optional PDF path or folder path.

### Behavior

If `$PdfPath` is:

* A PDF file: the script opens that PDF directly.
* A folder: the script lists PDF files from that folder.
* Blank: the script uses the folder where `book-speech-menu.ps1` is located and lists PDF files from there.

### Example

```powershell
pwsh ./book-speech-menu.ps1
```

Lists PDFs from the script folder.

```powershell
pwsh ./book-speech-menu.ps1 "./book.pdf"
```

Uses `book.pdf` directly.

```powershell
pwsh ./book-speech-menu.ps1 "/home/teo/Documents"
```

Lists PDFs from `/home/teo/Documents`.

---

## Function: `Test-RequiredCommand`

```powershell
function Test-RequiredCommand {
    param(
        [string]$CommandName,
        [string]$InstallMessage
    )

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        Write-Host "$CommandName is not installed." -ForegroundColor Red
        Write-Host $InstallMessage -ForegroundColor Yellow
        exit 1
    }
}
```

### Purpose

Checks whether a required Linux command is installed before the script tries to use it.

### Why This Matters

The script depends on external Linux tools. If one of them is missing, the script would fail later. This function catches the problem early and gives the user the install command.

### Used For

The script checks for:

```powershell
pdftotext
pdfinfo
spd-say
ocrmypdf
```

### Important Code

```powershell
Get-Command $CommandName -ErrorAction SilentlyContinue
```

This checks whether the command exists without displaying an ugly error if it does not.

---

## Function: `Get-ScriptFolder`

```powershell
function Get-ScriptFolder {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    return (Get-Location).Path
}
```

### Purpose

Finds the folder where the script is located.

### Why This Matters

This supports the feature where the script lists PDFs from its own folder when the user does not provide a path.

### Important Code

```powershell
$PSScriptRoot
```

`$PSScriptRoot` is an automatic PowerShell variable that contains the folder path of the running script.

### Fallback

```powershell
(Get-Location).Path
```

If `$PSScriptRoot` is unavailable, the script uses the current terminal folder.

---

## Function: `Select-PdfFile`

```powershell
function Select-PdfFile {
    param(
        [string]$InitialPath
    )
```

### Purpose

Handles PDF selection.

This is one of the most important functions in the script.

### What It Does

`Select-PdfFile`:

1. Checks whether the user provided a path.
2. If the path is a PDF, returns that PDF.
3. If the path is a folder, lists PDFs from that folder.
4. If no path is provided, lists PDFs from the script folder.
5. Allows selecting a PDF by number.
6. Allows manual path entry.
7. Allows changing folders.
8. Allows refreshing the PDF list.
9. Allows quitting.

### Important Code

```powershell
$defaultFolder = Get-ScriptFolder
```

This sets the default PDF folder to the script folder.

```powershell
$pdfFiles = Get-ChildItem -Path $defaultFolder -Filter "*.pdf" -File -ErrorAction SilentlyContinue |
    Sort-Object Name
```

This finds all PDF files in the selected folder and sorts them by name.

```powershell
return $pdfFiles[$selectedNumber - 1].FullName
```

This returns the full path of the PDF selected by the user.

### User Options

| Option | Action                      |
| ------ | --------------------------- |
| Number | Selects a PDF from the list |
| `M`    | Manually enter a PDF path   |
| `F`    | Change folder               |
| `R`    | Refresh PDF list            |
| `Q`    | Quit                        |

---

## Function: `Get-SearchablePdfPath`

```powershell
function Get-SearchablePdfPath {
    param(
        [string]$PdfFile
    )

    $folder = Split-Path $PdfFile
    $fileName = [System.IO.Path]::GetFileName($PdfFile)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($PdfFile)

    if ($fileName.ToLower().EndsWith(".searchable.pdf")) {
        return $PdfFile
    }

    return (Join-Path $folder "$baseName.searchable.pdf")
}
```

### Purpose

Creates the filename for the OCR-searchable PDF.

### Example

Original file:

```text
network-book.pdf
```

Searchable OCR file:

```text
network-book.searchable.pdf
```

### Important Code

```powershell
if ($fileName.ToLower().EndsWith(".searchable.pdf")) {
    return $PdfFile
}
```

This prevents the script from creating filenames like:

```text
book.searchable.searchable.pdf
```

---

## Function: `Get-PdfPageCount`

```powershell
function Get-PdfPageCount {
    param(
        [string]$PdfFile
    )

    $info = & pdfinfo "$PdfFile" 2>$null
    $pageLine = $info | Where-Object { $_ -match "^Pages:\s+\d+" } | Select-Object -First 1

    if (-not $pageLine) {
        throw "Could not determine page count."
    }

    return [int](([regex]::Match($pageLine, "\d+")).Value)
}
```

### Purpose

Gets the total number of pages in the selected PDF.

### External Tool Used

```bash
pdfinfo
```

### Important Code

```powershell
$pageLine = $info | Where-Object { $_ -match "^Pages:\s+\d+" }
```

This finds the line from `pdfinfo` output that looks like:

```text
Pages: 350
```

```powershell
return [int](([regex]::Match($pageLine, "\d+")).Value)
```

This extracts the page number and converts it to an integer.

### Used By

* Search whole PDF
* Read one page
* Read page range
* Show page count
* Validate user-entered page numbers

---

## Function: `Get-PdfText`

```powershell
function Get-PdfText {
    param(
        [string]$PdfFile,
        [int]$StartPage,
        [int]$EndPage
    )

    $tempTextFile = "/tmp/pdf-text-$([guid]::NewGuid()).txt"

    & pdftotext -layout -f $StartPage -l $EndPage "$PdfFile" "$tempTextFile" 2>$null

    if (-not (Test-Path $tempTextFile)) {
        return ""
    }

    $text = Get-Content "$tempTextFile" -Raw
    Remove-Item "$tempTextFile" -ErrorAction SilentlyContinue

    return $text
}
```

### Purpose

Extracts text from a PDF page or page range.

### External Tool Used

```bash
pdftotext
```

### Important Code

```powershell
pdftotext -layout -f $StartPage -l $EndPage "$PdfFile" "$tempTextFile"
```

This extracts text from the selected page range.

### Key Options

| Option    | Meaning                                       |
| --------- | --------------------------------------------- |
| `-layout` | Attempts to preserve the original page layout |
| `-f`      | First page to extract                         |
| `-l`      | Last page to extract                          |

### Temporary File

```powershell
$tempTextFile = "/tmp/pdf-text-$([guid]::NewGuid()).txt"
```

The script writes extracted PDF text to a temporary file.

The GUID prevents filename conflicts.

### Cleanup

```powershell
Remove-Item "$tempTextFile" -ErrorAction SilentlyContinue
```

Deletes the temporary text file after reading it.

---

## Function Group: Paged Output

Functions:

```powershell
Start-PagedOutput
Get-ConsoleLineCount
Write-PagedHost
```

### Purpose

Prevents long search results from scrolling off the screen too quickly.

When the screen fills up, the script pauses and waits for the user to press Enter.

---

## Function: `Start-PagedOutput`

```powershell
function Start-PagedOutput {
    try {
        $script:PagedOutputMaxLines = [Math]::Max(5, [Console]::WindowHeight - 3)
    }
    catch {
        $script:PagedOutputMaxLines = 20
    }

    $script:PagedOutputLineCount = 0
}
```

### Purpose

Initializes the screen paging system.

### Important Code

```powershell
[Console]::WindowHeight - 3
```

This estimates how many lines can fit in the terminal before pausing.

### Script-Level Variables

```powershell
$script:PagedOutputMaxLines
$script:PagedOutputLineCount
```

These variables are available across functions in the running script.

---

## Function: `Get-ConsoleLineCount`

```powershell
function Get-ConsoleLineCount {
    param(
        [string]$Text
    )
```

### Purpose

Estimates how many terminal rows a line of text will use.

### Why This Matters

A long line may wrap across multiple rows. This function accounts for that when deciding when to pause output.

### Important Code

```powershell
$count += [Math]::Max(1, [Math]::Ceiling($line.Length / $width))
```

This calculates wrapped line count based on terminal width.

---

## Function: `Write-PagedHost`

```powershell
function Write-PagedHost {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor
    )
```

### Purpose

Works like `Write-Host`, but pauses output when the screen is full.

### Important Code

```powershell
if ($script:PagedOutputLineCount -ge $script:PagedOutputMaxLines) {
    Write-Host ""
    Write-Host "Press Enter to continue search results..." -ForegroundColor Yellow
    [void][Console]::ReadLine()

    $script:PagedOutputLineCount = 0
}
```

This pauses search output and waits for Enter.

---

## Function Group: Speech Stop Control

Functions:

```powershell
Test-SpeechStopKey
Invoke-SpeechChunk
Speak-Text
```

### Purpose

Allows the user to stop speech while the PDF is being read aloud.

The user can press:

```text
S
Q
Esc
```

to stop speech.

---

## Function: `Test-SpeechStopKey`

```powershell
function Test-SpeechStopKey {
    try {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            if (
                $key.Key -eq [ConsoleKey]::S -or
                $key.Key -eq [ConsoleKey]::Q -or
                $key.Key -eq [ConsoleKey]::Escape
            ) {
                return $true
            }
        }
    }
    catch {
        return $false
    }

    return $false
}
```

### Purpose

Checks whether the user pressed a stop key while audio is playing.

### Important Code

```powershell
[Console]::KeyAvailable
```

Checks whether a key has been pressed without stopping the script.

```powershell
[Console]::ReadKey($true)
```

Reads the key without displaying it on the screen.

### Stop Keys

| Key   | Action      |
| ----- | ----------- |
| `S`   | Stop speech |
| `Q`   | Stop speech |
| `Esc` | Stop speech |

---

## Function: `Invoke-SpeechChunk`

```powershell
function Invoke-SpeechChunk {
    param(
        [string]$Text
    )
```

### Purpose

Speaks one chunk of text and checks for stop keys while the audio is playing.

### Why This Function Exists

The original version used:

```powershell
spd-say -w "$chunk"
```

That waited until the audio finished before returning control to PowerShell.

This function starts `spd-say` as a process so the script can monitor keyboard input while the audio is playing.

### Important Code

```powershell
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = "spd-say"
$psi.UseShellExecute = $false
$psi.ArgumentList.Add("-w")
$psi.ArgumentList.Add($Text)
```

This builds the `spd-say` process call safely.

```powershell
$process = [System.Diagnostics.Process]::Start($psi)
```

Starts the speech process.

```powershell
while (-not $process.HasExited) {
```

Keeps checking while the voice is still speaking.

```powershell
if (Test-SpeechStopKey) {
    spd-say --cancel
```

Cancels speech if the user presses `S`, `Q`, or `Esc`.

```powershell
$process.Kill()
```

Attempts to stop the running speech process if it is still active.

---

## Function: `Speak-Text`

```powershell
function Speak-Text {
    param(
        [string]$Text
    )
```

### Purpose

Reads text aloud using `spd-say`.

### What It Does

1. Cleans extra whitespace.
2. Splits long text into sentences.
3. Groups sentences into manageable chunks.
4. Sends each chunk to `Invoke-SpeechChunk`.
5. Allows the user to stop audio while it is playing.

### Important Code

```powershell
$cleanText = $Text -replace "\s+", " "
```

Removes extra spaces, tabs, and line breaks.

```powershell
$sentences = $cleanText -split "(?<=[.!?])\s+"
```

Splits text after punctuation marks.

```powershell
$maxLength = 800
```

Limits each speech chunk to about 800 characters.

This helps prevent `spd-say` from choking on very long text.

```powershell
$continueSpeaking = Invoke-SpeechChunk -Text $chunk
```

Sends each chunk to the function that supports stopping speech.

---

## Function: `Invoke-PdfOcr`

```powershell
function Invoke-PdfOcr {
    param(
        [string]$PdfFile,
        [bool]$ForceOcr = $false
    )
```

### Purpose

Creates or uses a searchable OCR copy of the selected PDF.

### External Tools Used

```bash
ocrmypdf
tesseract-ocr
```

### What It Does

1. Checks whether `ocrmypdf` is installed.
2. Determines the searchable PDF output path.
3. Uses an existing searchable PDF if one already exists.
4. Allows forcing OCR from scratch.
5. Creates a searchable PDF using OCR.

### Important Code

```powershell
$searchablePdf = Get-SearchablePdfPath $PdfFile
```

Gets the output file path.

```powershell
if ((Test-Path $searchablePdf) -and (-not $ForceOcr)) {
    return (Resolve-Path $searchablePdf).Path
}
```

Reuses an existing OCR PDF.

```powershell
"--skip-text"
```

Skips OCR on pages that already contain text.

```powershell
"--force-ocr"
```

Forces OCR even if the PDF already contains text.

```powershell
"--deskew"
```

Straightens tilted scanned pages.

```powershell
"--rotate-pages"
```

Attempts to rotate pages correctly.

```powershell
"-l", "eng"
```

Uses English OCR.

---

## Function: `Read-PdfPages`

```powershell
function Read-PdfPages {
    param(
        [string]$PdfFile,
        [int]$StartPage,
        [int]$EndPage
    )
```

### Purpose

Reads one page or a page range aloud.

### What It Does

1. Extracts text using `Get-PdfText`.
2. Checks whether text was found.
3. Sends the text to `Speak-Text`.

### Important Code

```powershell
$text = Get-PdfText -PdfFile $PdfFile -StartPage $StartPage -EndPage $EndPage
```

Extracts the text.

```powershell
$completed = Speak-Text -Text $text
```

Reads the extracted text aloud.

---

## Function: `Invoke-SearchResultReader`

```powershell
function Invoke-SearchResultReader {
    param(
        [string]$PdfFile,
        [object]$SearchMatches
    )
```

### Purpose

Allows the user to choose what to read after a search.

This function is triggered after search results are displayed.

### User Commands

| Command | Meaning                                    |
| ------- | ------------------------------------------ |
| `1`     | Read matching line number 1                |
| `c1`    | Read matching line 1 with context          |
| `p1`    | Read the full page where match 1 was found |
| `a`     | Read all matching lines                    |
| `Enter` | Return to menu                             |

### Important Code

```powershell
if ($choiceClean -match "^p\s*(\d+)$") {
```

Detects commands like:

```text
p1
p 1
```

This means read the whole page for match number 1.

```powershell
if ($choiceClean -match "^c\s*(\d+)$") {
```

Detects commands like:

```text
c1
c 1
```

This means read the match with context.

```powershell
if ([int]::TryParse($choiceClean, [ref]$matchNumberOnly)) {
```

Detects plain match numbers like:

```text
1
2
3
```

This means read only that matching line.

```powershell
Read-PdfPages -PdfFile $PdfFile -StartPage $item.Page -EndPage $item.Page
```

Reads the full page where a match was found.

---

## Function: `Search-PdfText`

```powershell
function Search-PdfText {
    param(
        [string]$PdfFile,
        [string]$SearchText,
        [int]$StartPage,
        [int]$EndPage,
        [int]$Context = 1,
        [bool]$ReadMatches = $false
    )
```

### Purpose

Searches PDF text for a word or phrase.

This is the main search function.

### What It Does

1. Initializes paged output.
2. Loops through each page.
3. Extracts text from each page.
4. Splits the page text into lines.
5. Searches each line.
6. Displays matching results.
7. Stores each result as an object.
8. Optionally reads matches aloud.
9. Calls `Invoke-SearchResultReader` so the user can choose what to read.

### Important Code

```powershell
Start-PagedOutput
```

Turns on screen paging for long search results.

```powershell
foreach ($pageNumber in $StartPage..$EndPage) {
```

Loops through the selected PDF pages.

```powershell
$pageText = Get-PdfText -PdfFile $PdfFile -StartPage $pageNumber -EndPage $pageNumber
```

Extracts one page of text at a time.

```powershell
$lines = $pageText -split "\r?\n"
```

Splits the page into individual lines.

```powershell
$found = $line.IndexOf($SearchText, [System.StringComparison]::CurrentCultureIgnoreCase) -ge 0
```

Performs a case-insensitive search.

This means searching for:

```text
tcp
```

will also match:

```text
TCP
Tcp
tCp
```

### Search Match Object

When a match is found, the script stores it as an object:

```powershell
$searchMatches.Add([pscustomobject]@{
    MatchNumber = $matchCount
    Page        = $pageNumber
    LineNumber  = $i + 1
    LineText    = $cleanLine
    ContextText = $contextText
}) | Out-Null
```

### Why This Object Matters

This object allows the script to remember:

* Which match number it was
* What page it was found on
* What extracted line it was found on
* The matching line text
* The surrounding context

That stored information is later used by `Invoke-SearchResultReader`.

---

## Function: `Search-WholePdf`

```powershell
function Search-WholePdf {
    param(
        [string]$PdfFile,
        [string]$SearchText,
        [bool]$ReadMatches = $false
    )
```

### Purpose

Searches the entire PDF.

### Why This Function Exists

The earlier version asked the user for a page range when searching. This function removes that step by automatically searching from page 1 to the final page.

### Important Code

```powershell
$totalPages = Get-PdfPageCount $PdfFile
```

Gets the final page number.

```powershell
Search-PdfText `
    -PdfFile $PdfFile `
    -SearchText $SearchText `
    -StartPage 1 `
    -EndPage $totalPages `
    -ReadMatches $ReadMatches
```

Searches from page 1 to the last page.

---

## Function: `Get-PageRangeFromUser`

```powershell
function Get-PageRangeFromUser {
    param(
        [string]$PdfFile,
        [bool]$SinglePage = $false
    )
```

### Purpose

Prompts the user for a page number or page range.

### Used By

* Menu option 3: read one page aloud
* Menu option 4: read page range aloud

### Not Used By Search

Search no longer uses this function because search now automatically searches the whole PDF.

### Important Code

```powershell
$totalPages = Get-PdfPageCount $PdfFile
```

Gets the total page count so input can be validated.

```powershell
if ($pageNumber -lt 1 -or $pageNumber -gt $totalPages)
```

Prevents invalid page numbers.

```powershell
return @{
    StartPage = $pageNumber
    EndPage   = $pageNumber
}
```

Returns a hashtable containing the selected page range.

---

## Function: `Show-Menu`

```powershell
function Show-Menu {
    param(
        [string]$CurrentPdf
    )
```

### Purpose

Displays the main menu.

### Important Code

```powershell
Clear-Host
```

Clears the terminal before showing the menu.

```powershell
Write-Host $CurrentPdf -ForegroundColor Green
```

Displays the current selected PDF.

### Current Menu

```text
1. Select different PDF
2. Create/use searchable OCR PDF
3. Read one page aloud
4. Read page range aloud
5. Search whole PDF
6. Search whole PDF and read matches aloud
7. Open current PDF
8. Stop speech
9. Show page count
0. Exit
```

---

## Startup Checks

```powershell
Test-RequiredCommand "pdftotext" "Install it with: sudo apt install poppler-utils"
Test-RequiredCommand "pdfinfo" "Install it with: sudo apt install poppler-utils"
Test-RequiredCommand "spd-say" "Install it with: sudo apt install speech-dispatcher"
```

### Purpose

Before the menu starts, the script checks for the minimum required tools.

### Why `ocrmypdf` Is Not Checked Here

`ocrmypdf` is only needed when the user chooses OCR from the menu.

The script checks for it inside `Invoke-PdfOcr`.

---

## Current PDF Selection

```powershell
$currentPdf = Select-PdfFile -InitialPath $PdfPath
```

### Purpose

Gets the first PDF to work with.

The selected PDF is stored in:

```powershell
$currentPdf
```

This variable is passed to the read, search, OCR, open, and page count functions.

---

## Main Menu Loop

```powershell
$running = $true

while ($running) {
    Show-Menu -CurrentPdf $currentPdf

    $choice = Read-Host "Choose an option"

    switch ($choice) {
```

### Purpose

Keeps the menu running until the user chooses option `0`.

### Important Code

```powershell
while ($running)
```

Keeps the script alive.

```powershell
switch ($choice)
```

Runs the correct block of code based on the user’s menu selection.

---

## Menu Option 1: Select Different PDF

```powershell
"1" {
    $currentPdf = Select-PdfFile
    Read-Host "Press Enter to continue"
}
```

### Purpose

Lets the user select another PDF without restarting the script.

---

## Menu Option 2: OCR PDF

```powershell
"2" {
    $forceAnswer = Read-Host "Force OCR from scratch? y/n"
    $forceOcr = $forceAnswer.Trim().ToLower() -in @("y", "yes")

    $currentPdf = Invoke-PdfOcr -PdfFile $currentPdf -ForceOcr $forceOcr

    Read-Host "Press Enter to continue"
}
```

### Purpose

Creates or uses a searchable OCR PDF.

### Important Code

```powershell
$currentPdf = Invoke-PdfOcr -PdfFile $currentPdf -ForceOcr $forceOcr
```

After OCR is complete, the current PDF changes to the searchable OCR PDF.

---

## Menu Option 3: Read One Page

```powershell
"3" {
    $range = Get-PageRangeFromUser -PdfFile $currentPdf -SinglePage $true

    if ($range) {
        Read-PdfPages -PdfFile $currentPdf -StartPage $range.StartPage -EndPage $range.EndPage
    }

    Read-Host "Press Enter to continue"
}
```

### Purpose

Reads a single page aloud.

---

## Menu Option 4: Read Page Range

```powershell
"4" {
    $range = Get-PageRangeFromUser -PdfFile $currentPdf -SinglePage $false

    if ($range) {
        Read-PdfPages -PdfFile $currentPdf -StartPage $range.StartPage -EndPage $range.EndPage
    }

    Read-Host "Press Enter to continue"
}
```

### Purpose

Reads multiple pages aloud.

---

## Menu Option 5: Search Whole PDF

```powershell
"5" {
    $searchText = Read-Host "Enter word or phrase to search"

    Search-WholePdf `
        -PdfFile $currentPdf `
        -SearchText $searchText `
        -ReadMatches $false

    Read-Host "Press Enter to continue"
}
```

### Purpose

Searches the entire PDF and displays all matches.

### After Search

After results are displayed, the script lets the user read:

* A matching line
* Context around a match
* The whole page where a match was found
* All matching lines

---

## Menu Option 6: Search and Read Matches

```powershell
"6" {
    $searchText = Read-Host "Enter word or phrase to search and read"

    Search-WholePdf `
        -PdfFile $currentPdf `
        -SearchText $searchText `
        -ReadMatches $true

    Read-Host "Press Enter to continue"
}
```

### Purpose

Searches the whole PDF and reads matching lines aloud.

---

## Menu Option 7: Open Current PDF

```powershell
"7" {
    if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
        xdg-open "$currentPdf" | Out-Null
    }
    else {
        Write-Host "xdg-open is not available." -ForegroundColor Red
    }

    Read-Host "Press Enter to continue"
}
```

### Purpose

Opens the selected PDF using the default Linux PDF viewer.

---

## Menu Option 8: Stop Speech

```powershell
"8" {
    spd-say --cancel
    Write-Host "Speech stopped." -ForegroundColor Yellow
    Read-Host "Press Enter to continue"
}
```

### Purpose

Stops any active or queued speech.

---

## Menu Option 9: Show Page Count

```powershell
"9" {
    $totalPages = Get-PdfPageCount $currentPdf
    Write-Host "Total pages: $totalPages" -ForegroundColor Green
    Read-Host "Press Enter to continue"
}
```

### Purpose

Displays the total number of pages in the current PDF.

---

## Menu Option 0: Exit

```powershell
"0" {
    spd-say --cancel
    Write-Host "Goodbye." -ForegroundColor Cyan
    $running = $false
}
```

### Purpose

Stops speech and exits the script.

### Important Code

```powershell
$running = $false
```

Ends the main menu loop.

---

# Important Data Flow

## Reading a Page

```text
User selects menu option 3 or 4
        ↓
Get-PageRangeFromUser
        ↓
Read-PdfPages
        ↓
Get-PdfText
        ↓
Speak-Text
        ↓
Invoke-SpeechChunk
        ↓
spd-say
```

---

## Searching the PDF

```text
User selects menu option 5 or 6
        ↓
Search-WholePdf
        ↓
Get-PdfPageCount
        ↓
Search-PdfText
        ↓
Get-PdfText for each page
        ↓
Search each extracted line
        ↓
Display numbered matches
        ↓
Store matches in search result objects
        ↓
Invoke-SearchResultReader
```

---

## OCR Process

```text
User selects menu option 2
        ↓
Invoke-PdfOcr
        ↓
Get-SearchablePdfPath
        ↓
ocrmypdf
        ↓
Create filename.searchable.pdf
        ↓
Set current PDF to searchable PDF
```

---

# Notes and Limitations

## Line Numbers

The line number shown in search results comes from the text extracted by `pdftotext`.

It may not perfectly match the visual line number on the PDF page because PDF text extraction depends on how the PDF stores text.

## Scanned PDFs

If a PDF is scanned or image-based, regular search may not find text.

Use menu option 2 first:

```text
2. Create/use searchable OCR PDF
```

## OCR Accuracy

OCR quality depends on:

* Scan quality
* Page rotation
* Font clarity
* Image resolution
* Language
* Contrast
* Whether the page contains columns, tables, or diagrams

## Speech Quality

Speech output depends on the Linux speech-dispatcher voice installed on the system.

## Case Sensitivity

Search is currently case-insensitive because the script uses:

```powershell
[System.StringComparison]::CurrentCultureIgnoreCase
```

---

# Recommended Future Improvements

Possible future improvements:

1. Add a case-sensitive search option.
2. Add export search results to a `.txt` file.
3. Add bookmark support.
4. Add resume reading from last page.
5. Add voice speed control.
6. Add voice selection.
7. Add OCR language selection.
8. Add support for searching only chapter ranges.
9. Add highlighting by opening the PDF to the matched page.
10. Add a search history menu.
