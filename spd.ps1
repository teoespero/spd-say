# ============================================================
# book-speech-menu.ps1
# ============================================================
# Menu-based PDF OCR, search, and speech reader for Ubuntu/Linux
# using PowerShell.
#
# Main features:
# - Lists PDFs from the script folder if no path is provided.
# - Lets the user select a PDF by number.
# - Can OCR scanned PDFs using ocrmypdf and tesseract.
# - Can search the whole PDF.
# - Search results show page and extracted line number.
# - User can read a matching line, context, full page, or all matches.
# - Can read one page or a page range aloud.
# - Allows speech to be stopped with S, Q, or Esc.
# - Pauses long search results when the terminal screen fills.
#
# Required Ubuntu packages:
# sudo apt update
# sudo apt install poppler-utils ocrmypdf tesseract-ocr tesseract-ocr-eng speech-dispatcher
#
# Run:
# pwsh ./book-speech-menu.ps1
#
# Or with a PDF:
# pwsh ./book-speech-menu.ps1 "./book.pdf"
# ============================================================

param(
    # Optional path to a PDF file or folder.
    # If blank, the script lists PDFs from the script folder.
    [string]$PdfPath
)

# ------------------------------------------------------------
# Function: Test-RequiredCommand
# Purpose:
# Checks if a required Linux command exists.
# If the command is missing, the script tells the user how to
# install it and exits.
# ------------------------------------------------------------

function Test-RequiredCommand {
    param(
        [string]$CommandName,
        [string]$InstallMessage
    )

    # Get-Command checks if the command exists.
    # -ErrorAction SilentlyContinue prevents an ugly error message.
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        Write-Host "$CommandName is not installed." -ForegroundColor Red
        Write-Host $InstallMessage -ForegroundColor Yellow
        exit 1
    }
}

# ------------------------------------------------------------
# Function: Get-ScriptFolder
# Purpose:
# Returns the folder where this script is located.
# This is used when the user does not provide a PDF path.
# ------------------------------------------------------------

function Get-ScriptFolder {
    # $PSScriptRoot is PowerShell's built-in variable for the
    # folder of the running script.
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    # Fallback: use the current terminal folder.
    return (Get-Location).Path
}

# ------------------------------------------------------------
# Function: Select-PdfFile
# Purpose:
# Lets the user select a PDF file.
#
# Behavior:
# - If a PDF path is passed in, use it.
# - If a folder path is passed in, list PDFs from that folder.
# - If no path is passed in, list PDFs from the script folder.
# - User can manually enter a path, change folder, refresh, or quit.
# ------------------------------------------------------------

function Select-PdfFile {
    param(
        [string]$InitialPath
    )

    # Default folder is where the script is located.
    $defaultFolder = Get-ScriptFolder

    # If user passed in an initial path, try to use it.
    if (-not [string]::IsNullOrWhiteSpace($InitialPath)) {
        # Remove extra quotes and spaces from user input.
        $InitialPath = $InitialPath.Trim().Trim("'").Trim('"')

        if (Test-Path $InitialPath) {
            $resolved = (Resolve-Path $InitialPath).Path

            # If the path is a folder, list PDFs from that folder.
            if ((Get-Item $resolved).PSIsContainer) {
                $defaultFolder = $resolved
            }
            # If the path is a PDF, use it immediately.
            elseif ([System.IO.Path]::GetExtension($resolved).ToLower() -eq ".pdf") {
                return $resolved
            }
            else {
                Write-Host "That path exists, but it is not a PDF." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
        else {
            Write-Host "PDF path not found: $InitialPath" -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }

    # Keep showing the PDF selection screen until a valid PDF is chosen.
    while ($true) {
        Clear-Host

        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host " SELECT A PDF FILE" -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Folder:" -ForegroundColor Yellow
        Write-Host $defaultFolder -ForegroundColor Green
        Write-Host ""

        # Get all PDF files from the selected folder.
        # The @() ensures the result is always treated as an array.
        $pdfFiles = @(
            Get-ChildItem -Path $defaultFolder -Filter "*.pdf" -File -ErrorAction SilentlyContinue |
            Sort-Object Name
        )

        if ($pdfFiles.Count -gt 0) {
            Write-Host "PDF files found:" -ForegroundColor Yellow
            Write-Host ""

            # Display numbered PDF list.
            for ($i = 0; $i -lt $pdfFiles.Count; $i++) {
                $number = $i + 1
                $sizeMB = [math]::Round($pdfFiles[$i].Length / 1MB, 2)
                $modified = $pdfFiles[$i].LastWriteTime.ToString("yyyy-MM-dd HH:mm")

                Write-Host "$number. $($pdfFiles[$i].Name)  [$sizeMB MB]  Modified: $modified"
            }

            Write-Host ""
        }
        else {
            Write-Host "No PDF files found in this folder." -ForegroundColor Red
            Write-Host ""
        }

        Write-Host "Options:"
        Write-Host "Enter a number to select a PDF"
        Write-Host "M. Manually enter PDF path"
        Write-Host "F. Change folder"
        Write-Host "R. Refresh"
        Write-Host "Q. Quit"
        Write-Host ""

        $choice = Read-Host "Choose a PDF or option"
        $choiceClean = $choice.Trim().ToLower()

        # Quit the script.
        if ($choiceClean -eq "q") {
            exit 0
        }

        # Refresh the current folder list.
        if ($choiceClean -eq "r") {
            continue
        }

        # Change the current folder.
        if ($choiceClean -eq "f") {
            $newFolder = Read-Host "Enter folder path"
            $newFolder = $newFolder.Trim().Trim("'").Trim('"')

            if (Test-Path $newFolder) {
                $resolvedFolder = (Resolve-Path $newFolder).Path

                if ((Get-Item $resolvedFolder).PSIsContainer) {
                    $defaultFolder = $resolvedFolder
                }
                else {
                    Write-Host "That is not a folder." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
            else {
                Write-Host "Folder not found." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }

            continue
        }

        # Manually enter a PDF path.
        if ($choiceClean -eq "m") {
            $manualPath = Read-Host "Enter PDF path"
            $manualPath = $manualPath.Trim().Trim("'").Trim('"')

            if (Test-Path $manualPath) {
                $resolved = (Resolve-Path $manualPath).Path

                if ([System.IO.Path]::GetExtension($resolved).ToLower() -eq ".pdf") {
                    return $resolved
                }
            }

            Write-Host "Invalid PDF path." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }

        # If user typed a number, select that PDF.
        $selectedNumber = 0

        if ([int]::TryParse($choice, [ref]$selectedNumber)) {
            if ($selectedNumber -ge 1 -and $selectedNumber -le $pdfFiles.Count) {
                return $pdfFiles[$selectedNumber - 1].FullName
            }
        }

        Write-Host "Invalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

# ------------------------------------------------------------
# Function: Get-SearchablePdfPath
# Purpose:
# Builds the output filename for the OCR-searchable PDF.
#
# Example:
# book.pdf becomes book.searchable.pdf
# ------------------------------------------------------------

function Get-SearchablePdfPath {
    param(
        [string]$PdfFile
    )

    $folder = Split-Path $PdfFile
    $fileName = [System.IO.Path]::GetFileName($PdfFile)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($PdfFile)

    # Prevent creating file names like:
    # book.searchable.searchable.pdf
    if ($fileName.ToLower().EndsWith(".searchable.pdf")) {
        return $PdfFile
    }

    return (Join-Path $folder "$baseName.searchable.pdf")
}

# ------------------------------------------------------------
# Function: Get-PdfPageCount
# Purpose:
# Uses pdfinfo to determine how many pages the PDF has.
# ------------------------------------------------------------

function Get-PdfPageCount {
    param(
        [string]$PdfFile
    )

    # Run pdfinfo and suppress error output.
    $info = & pdfinfo "$PdfFile" 2>$null

    # Look for the line that starts with "Pages:"
    $pageLine = $info | Where-Object { $_ -match "^Pages:\s+\d+" } | Select-Object -First 1

    if (-not $pageLine) {
        throw "Could not determine page count."
    }

    # Extract the page number from the line and return it as an integer.
    return [int](([regex]::Match($pageLine, "\d+")).Value)
}

# ------------------------------------------------------------
# Function: Get-PdfText
# Purpose:
# Extracts text from a PDF page or page range using pdftotext.
# ------------------------------------------------------------

function Get-PdfText {
    param(
        [string]$PdfFile,
        [int]$StartPage,
        [int]$EndPage
    )

    # Temporary text file used by pdftotext.
    # GUID keeps the filename unique.
    $tempTextFile = "/tmp/pdf-text-$([guid]::NewGuid()).txt"

    # -layout tries to preserve the original layout.
    # -f is the first page.
    # -l is the last page.
    & pdftotext -layout -f $StartPage -l $EndPage "$PdfFile" "$tempTextFile" 2>$null

    if (-not (Test-Path $tempTextFile)) {
        return ""
    }

    # Read the extracted text.
    $text = Get-Content "$tempTextFile" -Raw

    # Clean up the temporary file.
    Remove-Item "$tempTextFile" -ErrorAction SilentlyContinue

    return $text
}

# ------------------------------------------------------------
# Paged Output Functions
# Purpose:
# Prevents search results from scrolling off the terminal.
# When the screen fills, the script pauses and waits for Enter.
# ------------------------------------------------------------

function Start-PagedOutput {
    try {
        # Use terminal height minus a few lines for the prompt.
        $script:PagedOutputMaxLines = [Math]::Max(5, [Console]::WindowHeight - 3)
    }
    catch {
        # Fallback if terminal size cannot be detected.
        $script:PagedOutputMaxLines = 20
    }

    # Track how many lines have been printed.
    $script:PagedOutputLineCount = 0
}

function Get-ConsoleLineCount {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return 1
    }

    try {
        # Get the current terminal width.
        $width = [Math]::Max(20, [Console]::WindowWidth)
    }
    catch {
        # Fallback width.
        $width = 80
    }

    # Split multiline text.
    $lines = $Text -split "\r?\n"
    $count = 0

    foreach ($line in $lines) {
        # Estimate wrapped lines based on terminal width.
        $count += [Math]::Max(1, [Math]::Ceiling($line.Length / $width))
    }

    return $count
}

function Write-PagedHost {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor
    )

    # Write with or without color.
    if ($PSBoundParameters.ContainsKey("ForegroundColor")) {
        Write-Host $Text -ForegroundColor $ForegroundColor
    }
    else {
        Write-Host $Text
    }

    # Count how many terminal rows this text likely used.
    $script:PagedOutputLineCount += Get-ConsoleLineCount -Text $Text

    # Pause when the screen is full.
    if ($script:PagedOutputLineCount -ge $script:PagedOutputMaxLines) {
        Write-Host ""
        Write-Host "Press Enter to continue search results..." -ForegroundColor Yellow
        [void][Console]::ReadLine()

        # Reset line count after user continues.
        $script:PagedOutputLineCount = 0
    }
}

# ------------------------------------------------------------
# Function: Test-SpeechStopKey
# Purpose:
# Checks if the user pressed S, Q, or Esc while speech is playing.
# ------------------------------------------------------------

function Test-SpeechStopKey {
    try {
        # Check all available key presses without blocking the script.
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            # These keys stop speech.
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
        # Some terminals may not support KeyAvailable.
        return $false
    }

    return $false
}

# ------------------------------------------------------------
# Function: Invoke-SpeechChunk
# Purpose:
# Reads one chunk of text aloud using spd-say.
# While the chunk is playing, the function watches for stop keys.
# ------------------------------------------------------------

function Invoke-SpeechChunk {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $true
    }

    # Build a safe process call for spd-say.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "spd-say"
    $psi.UseShellExecute = $false

    # -w tells spd-say to wait until speaking finishes.
    $psi.ArgumentList.Add("-w")

    # Add the text as one argument.
    $psi.ArgumentList.Add($Text)

    # Start the speech process.
    $process = [System.Diagnostics.Process]::Start($psi)

    # While speech is still running, check for stop keys.
    while (-not $process.HasExited) {
        if (Test-SpeechStopKey) {
            # Cancel queued/current speech.
            spd-say --cancel

            try {
                # Kill the speech process if it is still running.
                if (-not $process.HasExited) {
                    $process.Kill()
                }
            }
            catch {
                # Ignore kill errors.
            }

            Write-Host ""
            Write-Host "Speech stopped." -ForegroundColor Yellow
            return $false
        }

        Start-Sleep -Milliseconds 100
    }

    return $true
}

# ------------------------------------------------------------
# Function: Speak-Text
# Purpose:
# Cleans and splits long text into smaller chunks, then reads
# each chunk aloud using Invoke-SpeechChunk.
# ------------------------------------------------------------

function Speak-Text {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $true
    }

    Write-Host ""
    Write-Host "Reading aloud..." -ForegroundColor Green
    Write-Host "Press S, Q, or Esc to stop speech." -ForegroundColor Yellow
    Write-Host ""

    # Replace repeated whitespace with a single space.
    $cleanText = $Text -replace "\s+", " "
    $cleanText = $cleanText.Trim()

    # Keep speech chunks at a reasonable size.
    $maxLength = 800

    # Split text into sentences using punctuation.
    $sentences = $cleanText -split "(?<=[.!?])\s+"

    $chunk = ""

    foreach ($sentence in $sentences) {
        # Build a chunk until it approaches the max size.
        if (($chunk.Length + $sentence.Length) -lt $maxLength) {
            $chunk += " $sentence"
        }
        else {
            # Speak the current chunk.
            if (-not [string]::IsNullOrWhiteSpace($chunk)) {
                $continueSpeaking = Invoke-SpeechChunk -Text $chunk

                if (-not $continueSpeaking) {
                    return $false
                }
            }

            # Start a new chunk.
            $chunk = $sentence
        }
    }

    # Speak the final chunk.
    if (-not [string]::IsNullOrWhiteSpace($chunk)) {
        $continueSpeaking = Invoke-SpeechChunk -Text $chunk

        if (-not $continueSpeaking) {
            return $false
        }
    }

    Write-Host "Done reading." -ForegroundColor Cyan
    return $true
}

# ------------------------------------------------------------
# Function: Invoke-PdfOcr
# Purpose:
# Creates or uses an OCR-searchable version of the PDF.
#
# Output:
# original.pdf becomes original.searchable.pdf
# ------------------------------------------------------------

function Invoke-PdfOcr {
    param(
        [string]$PdfFile,

        # If true, OCR is forced even if the PDF already has text.
        [bool]$ForceOcr = $false
    )

    # OCR is only needed when user chooses option 2,
    # so ocrmypdf is checked here instead of at startup.
    Test-RequiredCommand "ocrmypdf" "Install it with: sudo apt install ocrmypdf tesseract-ocr tesseract-ocr-eng"

    $searchablePdf = Get-SearchablePdfPath $PdfFile

    # If searchable PDF already exists and user did not force OCR,
    # use the existing searchable copy.
    if ((Test-Path $searchablePdf) -and (-not $ForceOcr)) {
        Write-Host "Searchable PDF already exists:" -ForegroundColor Yellow
        Write-Host $searchablePdf -ForegroundColor Cyan
        return (Resolve-Path $searchablePdf).Path
    }

    # Remove existing searchable PDF if force OCR is requested.
    if ((Test-Path $searchablePdf) -and $ForceOcr) {
        Remove-Item $searchablePdf -Force
    }

    Write-Host "Creating searchable OCR PDF..." -ForegroundColor Green
    Write-Host "This may take a while for large books." -ForegroundColor Yellow

    if ($ForceOcr) {
        # --force-ocr OCRs even pages that already have text.
        $ocrArgs = @(
            "--force-ocr",
            "--deskew",
            "--rotate-pages",
            "-l", "eng",
            $PdfFile,
            $searchablePdf
        )
    }
    else {
        # --skip-text skips pages that already contain text.
        $ocrArgs = @(
            "--skip-text",
            "--deskew",
            "--rotate-pages",
            "-l", "eng",
            $PdfFile,
            $searchablePdf
        )
    }

    # Run ocrmypdf with the selected arguments.
    & ocrmypdf @ocrArgs

    # Check exit code from ocrmypdf.
    if ($LASTEXITCODE -ne 0) {
        Write-Host "OCR failed." -ForegroundColor Red

        # Return original PDF if OCR failed.
        return $PdfFile
    }

    Write-Host "Searchable PDF created:" -ForegroundColor Green
    Write-Host $searchablePdf -ForegroundColor Cyan

    return $searchablePdf
}

# ------------------------------------------------------------
# Function: Read-PdfPages
# Purpose:
# Reads a single page or page range aloud.
# ------------------------------------------------------------

function Read-PdfPages {
    param(
        [string]$PdfFile,
        [int]$StartPage,
        [int]$EndPage
    )

    Write-Host "Extracting text from pages $StartPage to $EndPage..." -ForegroundColor Green

    # Extract text from the requested page range.
    $text = Get-PdfText -PdfFile $PdfFile -StartPage $StartPage -EndPage $EndPage

    if ([string]::IsNullOrWhiteSpace($text)) {
        Write-Host "No readable text found." -ForegroundColor Red
        Write-Host "Try OCR first from the menu." -ForegroundColor Yellow
        return
    }

    # Read extracted text aloud.
    $completed = Speak-Text -Text $text

    if ($completed) {
        Write-Host "Finished reading pages $StartPage to $EndPage." -ForegroundColor Cyan
    }
}

# ------------------------------------------------------------
# Function: Invoke-SearchResultReader
# Purpose:
# After search results are found, this function lets the user
# choose which result to read aloud.
#
# Supported commands:
# 1      = read matching line 1
# c1     = read match 1 with context
# p1     = read the whole page where match 1 was found
# a      = read all matching lines
# Enter  = return to main menu
# ------------------------------------------------------------

function Invoke-SearchResultReader {
    param(
        [string]$PdfFile,

        # Search result objects created by Search-PdfText.
        [object]$SearchMatches
    )

    if ($null -eq $SearchMatches -or $SearchMatches.Count -eq 0) {
        return
    }

    while ($true) {
        Write-Host ""
        Write-Host "Read search result options:" -ForegroundColor Cyan
        Write-Host "  Enter match number   = read that matching line"
        Write-Host "  p<number>            = read the whole page for that match"
        Write-Host "  c<number>            = read that match with context"
        Write-Host "  a                    = read all matching lines"
        Write-Host "  Enter                = return to menu"
        Write-Host ""
        Write-Host "Examples: 1, p1, c1, a" -ForegroundColor Yellow
        Write-Host ""

        $choice = Read-Host "Choose result to read"
        $choiceClean = $choice.Trim().ToLower()

        # Blank input returns to menu.
        if ([string]::IsNullOrWhiteSpace($choiceClean)) {
            return
        }

        # Read all matching lines.
        if ($choiceClean -eq "a") {
            foreach ($item in $SearchMatches) {
                $textToSpeak = "Match $($item.MatchNumber). Page $($item.Page), line $($item.LineNumber). $($item.LineText)"
                $completed = Speak-Text -Text $textToSpeak

                if (-not $completed) {
                    return
                }
            }

            continue
        }

        # p<number> reads the whole page where a match was found.
        if ($choiceClean -match "^p\s*(\d+)$") {
            $matchNumber = [int]$Matches[1]

            $item = $SearchMatches |
                Where-Object { $_.MatchNumber -eq $matchNumber } |
                Select-Object -First 1

            if ($null -eq $item) {
                Write-Host "Invalid match number." -ForegroundColor Red
                continue
            }

            Write-Host "Reading page $($item.Page) for match $matchNumber..." -ForegroundColor Green
            Read-PdfPages -PdfFile $PdfFile -StartPage $item.Page -EndPage $item.Page
            continue
        }

        # c<number> reads the match with surrounding context.
        if ($choiceClean -match "^c\s*(\d+)$") {
            $matchNumber = [int]$Matches[1]

            $item = $SearchMatches |
                Where-Object { $_.MatchNumber -eq $matchNumber } |
                Select-Object -First 1

            if ($null -eq $item) {
                Write-Host "Invalid match number." -ForegroundColor Red
                continue
            }

            $textToSpeak = "Match $($item.MatchNumber). Page $($item.Page), line $($item.LineNumber). Context. $($item.ContextText)"
            $completed = Speak-Text -Text $textToSpeak

            if (-not $completed) {
                return
            }

            continue
        }

        # Plain number reads only the matching line.
        $matchNumberOnly = 0

        if ([int]::TryParse($choiceClean, [ref]$matchNumberOnly)) {
            $item = $SearchMatches |
                Where-Object { $_.MatchNumber -eq $matchNumberOnly } |
                Select-Object -First 1

            if ($null -eq $item) {
                Write-Host "Invalid match number." -ForegroundColor Red
                continue
            }

            $textToSpeak = "Match $($item.MatchNumber). Page $($item.Page), line $($item.LineNumber). $($item.LineText)"
            $completed = Speak-Text -Text $textToSpeak

            if (-not $completed) {
                return
            }

            continue
        }

        Write-Host "Invalid option." -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# Function: Search-PdfText
# Purpose:
# Searches PDF text for a word or phrase.
#
# Notes:
# - Search is case-insensitive.
# - It searches line by line.
# - Each result is stored as an object so the user can read it later.
# ------------------------------------------------------------

function Search-PdfText {
    param(
        [string]$PdfFile,
        [string]$SearchText,
        [int]$StartPage,
        [int]$EndPage,

        # Number of lines before and after the match to display.
        [int]$Context = 1,

        # If true, matching lines are read aloud after search.
        [bool]$ReadMatches = $false
    )

    # Initialize paged output for long search results.
    Start-PagedOutput

    Write-PagedHost ""
    Write-PagedHost "Searching for: $SearchText" -ForegroundColor Green
    Write-PagedHost "Pages: $StartPage to $EndPage" -ForegroundColor Cyan
    Write-PagedHost ""

    $matchCount = 0

    # List of spoken match strings.
    $spokenMatches = New-Object System.Collections.Generic.List[string]

    # List of structured match objects.
    $searchMatches = New-Object System.Collections.Generic.List[object]

    # Search one page at a time.
    foreach ($pageNumber in $StartPage..$EndPage) {
        Write-Progress `
            -Activity "Searching PDF" `
            -Status "Searching page $pageNumber of $EndPage" `
            -PercentComplete (($pageNumber / $EndPage) * 100)

        # Extract current page text.
        $pageText = Get-PdfText -PdfFile $PdfFile -StartPage $pageNumber -EndPage $pageNumber

        if ([string]::IsNullOrWhiteSpace($pageText)) {
            continue
        }

        # Split page text into lines.
        $lines = $pageText -split "\r?\n"

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            # Case-insensitive search.
            # Searching "tcp" will match "TCP", "Tcp", etc.
            $found = $line.IndexOf($SearchText, [System.StringComparison]::CurrentCultureIgnoreCase) -ge 0

            if ($found) {
                $matchCount++

                Write-PagedHost "[$matchCount] Page $pageNumber, line $($i + 1)" -ForegroundColor Yellow

                # Build context range.
                $fromLine = [Math]::Max(0, $i - $Context)
                $toLine = [Math]::Min($lines.Count - 1, $i + $Context)

                $contextLines = New-Object System.Collections.Generic.List[string]

                # Display matching line and context.
                for ($j = $fromLine; $j -le $toLine; $j++) {
                    $contextLines.Add($lines[$j]) | Out-Null

                    if ($j -eq $i) {
                        # Matching line is shown with >
                        Write-PagedHost "> $($lines[$j])" -ForegroundColor Green
                    }
                    else {
                        Write-PagedHost "  $($lines[$j])"
                    }
                }

                Write-PagedHost ""

                $cleanLine = $line.Trim()
                $contextText = ($contextLines -join " ").Trim()

                # Store a speech-friendly match.
                $spokenMatches.Add("Match $matchCount. Page $pageNumber, line $($i + 1). $cleanLine") | Out-Null

                # Store structured match info for later reading.
                $searchMatches.Add([pscustomobject]@{
                    MatchNumber = $matchCount
                    Page        = $pageNumber
                    LineNumber  = $i + 1
                    LineText    = $cleanLine
                    ContextText = $contextText
                }) | Out-Null
            }
        }
    }

    Write-Progress -Activity "Searching PDF" -Completed

    if ($matchCount -eq 0) {
        Write-PagedHost "No matches found." -ForegroundColor Red
        Write-PagedHost "If this is scanned, run OCR first from the menu." -ForegroundColor Yellow
        return
    }

    Write-PagedHost "Total matches found: $matchCount" -ForegroundColor Green

    # If requested, read all matching lines aloud.
    if ($ReadMatches -and $spokenMatches.Count -gt 0) {
        Write-Host ""
        Write-Host "Reading matches aloud..." -ForegroundColor Green

        foreach ($match in $spokenMatches) {
            $completed = Speak-Text -Text $match

            if (-not $completed) {
                return
            }
        }
    }

    # Let the user choose a result to read.
    Invoke-SearchResultReader -PdfFile $PdfFile -SearchMatches $searchMatches
}

# ------------------------------------------------------------
# Function: Search-WholePdf
# Purpose:
# Searches from page 1 to the last page automatically.
# This removes the need to ask the user for a search range.
# ------------------------------------------------------------

function Search-WholePdf {
    param(
        [string]$PdfFile,
        [string]$SearchText,
        [bool]$ReadMatches = $false
    )

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-Host "Search text cannot be blank." -ForegroundColor Red
        return
    }

    # Determine total page count.
    $totalPages = Get-PdfPageCount $PdfFile

    Write-Host ""
    Write-Host "Searching the whole PDF..." -ForegroundColor Cyan
    Write-Host "Pages: 1 to $totalPages" -ForegroundColor Cyan

    # Search from first page to last page.
    Search-PdfText `
        -PdfFile $PdfFile `
        -SearchText $SearchText `
        -StartPage 1 `
        -EndPage $totalPages `
        -ReadMatches $ReadMatches
}

# ------------------------------------------------------------
# Function: Get-PageRangeFromUser
# Purpose:
# Prompts user for one page or a page range.
# Used for reading pages aloud, not for searching.
# ------------------------------------------------------------

function Get-PageRangeFromUser {
    param(
        [string]$PdfFile,

        # If true, ask only for one page.
        # If false, ask for start and end page.
        [bool]$SinglePage = $false
    )

    $totalPages = Get-PdfPageCount $PdfFile

    if ($SinglePage) {
        $pageInput = Read-Host "Enter page number 1-$totalPages"
        $pageNumber = 0

        if (-not [int]::TryParse($pageInput, [ref]$pageNumber)) {
            Write-Host "Invalid page number." -ForegroundColor Red
            return $null
        }

        if ($pageNumber -lt 1 -or $pageNumber -gt $totalPages) {
            Write-Host "Page must be between 1 and $totalPages." -ForegroundColor Red
            return $null
        }

        return @{
            StartPage = $pageNumber
            EndPage   = $pageNumber
        }
    }
    else {
        $startInput = Read-Host "Start page 1-$totalPages"
        $endInput = Read-Host "End page 1-$totalPages"

        $startPage = 0
        $endPage = 0

        if (-not [int]::TryParse($startInput, [ref]$startPage)) {
            Write-Host "Invalid start page." -ForegroundColor Red
            return $null
        }

        if (-not [int]::TryParse($endInput, [ref]$endPage)) {
            Write-Host "Invalid end page." -ForegroundColor Red
            return $null
        }

        if ($startPage -lt 1 -or $endPage -gt $totalPages -or $startPage -gt $endPage) {
            Write-Host "Invalid page range." -ForegroundColor Red
            return $null
        }

        return @{
            StartPage = $startPage
            EndPage   = $endPage
        }
    }
}

# ------------------------------------------------------------
# Function: Show-Menu
# Purpose:
# Displays the main menu and shows the currently selected PDF.
# ------------------------------------------------------------

function Show-Menu {
    param(
        [string]$CurrentPdf
    )

    Clear-Host

    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " PDF OCR, SEARCH, AND SPEECH MENU" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current PDF:" -ForegroundColor Yellow
    Write-Host $CurrentPdf -ForegroundColor Green
    Write-Host ""
    Write-Host "1. Select different PDF"
    Write-Host "2. Create/use searchable OCR PDF"
    Write-Host "3. Read one page aloud"
    Write-Host "4. Read page range aloud"
    Write-Host "5. Search whole PDF"
    Write-Host "6. Search whole PDF and read matches aloud"
    Write-Host "7. Open current PDF"
    Write-Host "8. Stop speech"
    Write-Host "9. Show page count"
    Write-Host "0. Exit"
    Write-Host ""
}

# ------------------------------------------------------------
# Startup checks
# Purpose:
# Make sure the minimum required tools are available.
# OCR tool is checked only when OCR is selected.
# ------------------------------------------------------------

Test-RequiredCommand "pdftotext" "Install it with: sudo apt install poppler-utils"
Test-RequiredCommand "pdfinfo" "Install it with: sudo apt install poppler-utils"
Test-RequiredCommand "spd-say" "Install it with: sudo apt install speech-dispatcher"

# ------------------------------------------------------------
# Select initial PDF
# ------------------------------------------------------------

$currentPdf = Select-PdfFile -InitialPath $PdfPath

# ------------------------------------------------------------
# Main menu loop
# Purpose:
# Keeps the program running until user chooses 0.
# ------------------------------------------------------------

$running = $true

while ($running) {
    Show-Menu -CurrentPdf $currentPdf

    $choice = Read-Host "Choose an option"

    switch ($choice) {
        # Select another PDF.
        "1" {
            $currentPdf = Select-PdfFile
            Read-Host "Press Enter to continue"
        }

        # Create or use searchable OCR PDF.
        "2" {
            $forceAnswer = Read-Host "Force OCR from scratch? y/n"
            $forceOcr = $forceAnswer.Trim().ToLower() -in @("y", "yes")

            # After OCR, current PDF becomes the searchable PDF.
            $currentPdf = Invoke-PdfOcr -PdfFile $currentPdf -ForceOcr $forceOcr

            Read-Host "Press Enter to continue"
        }

        # Read one page aloud.
        "3" {
            $range = Get-PageRangeFromUser -PdfFile $currentPdf -SinglePage $true

            if ($range) {
                Read-PdfPages -PdfFile $currentPdf -StartPage $range.StartPage -EndPage $range.EndPage
            }

            Read-Host "Press Enter to continue"
        }

        # Read a page range aloud.
        "4" {
            $range = Get-PageRangeFromUser -PdfFile $currentPdf -SinglePage $false

            if ($range) {
                Read-PdfPages -PdfFile $currentPdf -StartPage $range.StartPage -EndPage $range.EndPage
            }

            Read-Host "Press Enter to continue"
        }

        # Search the whole PDF.
        "5" {
            $searchText = Read-Host "Enter word or phrase to search"

            Search-WholePdf `
                -PdfFile $currentPdf `
                -SearchText $searchText `
                -ReadMatches $false

            Read-Host "Press Enter to continue"
        }

        # Search the whole PDF and read matches aloud.
        "6" {
            $searchText = Read-Host "Enter word or phrase to search and read"

            Search-WholePdf `
                -PdfFile $currentPdf `
                -SearchText $searchText `
                -ReadMatches $true

            Read-Host "Press Enter to continue"
        }

        # Open the current PDF in the default Linux PDF viewer.
        "7" {
            if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                xdg-open "$currentPdf" | Out-Null
            }
            else {
                Write-Host "xdg-open is not available." -ForegroundColor Red
            }

            Read-Host "Press Enter to continue"
        }

        # Stop active or queued speech.
        "8" {
            spd-say --cancel
            Write-Host "Speech stopped." -ForegroundColor Yellow
            Read-Host "Press Enter to continue"
        }

        # Show page count.
        "9" {
            $totalPages = Get-PdfPageCount $currentPdf
            Write-Host "Total pages: $totalPages" -ForegroundColor Green
            Read-Host "Press Enter to continue"
        }

        # Exit.
        "0" {
            spd-say --cancel
            Write-Host "Goodbye." -ForegroundColor Cyan
            $running = $false
        }

        # Invalid menu option.
        default {
            Write-Host "Invalid option." -ForegroundColor Red
            Read-Host "Press Enter to continue"
        }
    }
}