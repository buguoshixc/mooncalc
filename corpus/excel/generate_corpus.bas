Attribute VB_Name = "MoonCalcCorpus"
Option Explicit

' MoonCalc answer-key corpus generator (desktop Excel).
' Reads corpus/spec/*.tsv (UTF-8), computes each case in real Excel,
' writes corpus/cases/<name>.json (schema mooncalc-corpus/1).
' Cases Excel rejects are skipped and logged to <name>.skipped.txt.
'
' Grid keys are "SHEET!A1" or a bare "A1". A bare address is the main
' temporary worksheet; extra worksheets are created on demand (last "!" wins,
' address part must be A1-shaped) and deleted again after the case, on the
' normal path and on every error path. The answer cell is always ZZ1 on the
' main temporary worksheet, so unquoted references inside a case formula hit
' the main sheet and other sheets have to be qualified in the formula itself.
'
' Optional 7th spec column "Name1=Ref1|Name2=Ref2" adds workbook names for the
' case only (removed again after the answer is read).

Sub GenerateCorpus()
    RunCorpus ""
End Sub

' Single-batch entry point for refs.tsv: reads corpus/spec/refs.tsv only and
' writes corpus/cases/refs.json + refs.skipped.txt only. The other cases files
' are left untouched (byte for byte).
Sub GenerateCorpusOne()
    RunCorpus "refs"
End Sub

Private Sub RunCorpus(onlyName As String)
    Dim fso As Object, base As String, specDir As String, outDir As String
    Set fso = CreateObject("Scripting.FileSystemObject")
    base = ThisWorkbook.Path
    specDir = base & "\..\spec"
    outDir = base & "\..\cases"
    If Not fso.FolderExists(specDir) Then
        MsgBox "spec dir not found: " & specDir
        Exit Sub
    End If
    If Len(onlyName) > 0 Then
        If Not fso.FileExists(specDir & "\" & onlyName & ".tsv") Then
            MsgBox "spec file not found: " & specDir & "\" & onlyName & ".tsv"
            Exit Sub
        End If
    End If
    If Not fso.FolderExists(outDir) Then fso.CreateFolder outDir

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Worksheets.Add
    ws.Name = FreeTempSheetName()

    Dim oldCalc As XlCalculation
    oldCalc = Application.Calculation
    Application.Calculation = xlCalculationManual
    Application.ScreenUpdating = False
    On Error GoTo Cleanup

    Dim f As Object, count As Long
    count = 0
    For Each f In fso.GetFolder(specDir).Files
        If LCase(fso.GetExtensionName(f.Name)) = "tsv" Then
            If Len(onlyName) = 0 Or LCase(fso.GetBaseName(f.Name)) = LCase(onlyName) Then
                ProcessSpec fso, f, ws, outDir
                count = count + 1
            End If
        End If
    Next f
    ' Fall-through path only: a stale handled error must not be reported as a
    ' killed run (the On Error handler jumps straight past this line).
    Err.Clear

Cleanup:
    Application.Calculation = oldCalc
    Application.ScreenUpdating = True
    If Not ws Is Nothing Then
        DeleteSheet ws
    End If
    If Err.Number <> 0 Then
        MsgBox "Stopped by error " & Err.Number & ": " & Err.Description & vbCrLf & _
               "Partial output (if any) is in corpus/cases. Report this to the AI."
    Else
        MsgBox "Corpus generation complete: " & count & " spec file(s)." & vbCrLf & _
               "Skipped cases (if any) are listed in corpus/cases/*.skipped.txt"
    End If
End Sub

Private Sub ProcessSpec(fso As Object, f As Object, ws As Worksheet, outDir As String)
    Dim line As String, parts() As String
    Dim records As String, first As Boolean
    Dim skipped As String
    Dim lines() As String, li As Long
    lines = Split(Replace(ReadUtf8(f.Path), vbCr, ""), vbLf)
    records = ""
    skipped = ""
    first = True
    For li = 0 To UBound(lines)
        line = lines(li)
        If Len(line) > 0 And Left(line, 1) <> "#" Then
            parts = Split(line, vbTab)
            If UBound(parts) >= 4 And parts(0) <> "id" Then
                Dim rec As String
                Dim iterSpec As String, namesSpec As String, skipReason As String
                iterSpec = ""
                namesSpec = ""
                If UBound(parts) >= 5 Then iterSpec = parts(5)
                If UBound(parts) >= 6 Then namesSpec = parts(6)
                skipReason = ""
                rec = EvalCase(ws, parts(0), parts(1), parts(2), parts(3), parts(4), _
                               iterSpec, namesSpec, skipReason)
                If Len(rec) = 0 Then
                    skipped = skipped & parts(0)
                    If Len(skipReason) > 0 Then skipped = skipped & vbTab & skipReason
                    skipped = skipped & vbLf
                Else
                    If Not first Then records = records & ","
                    records = records & rec
                    first = False
                End If
            End If
        End If
    Next li
    Dim out As String
    out = "{""schema"":""mooncalc-corpus/1"",""records"":[" & records & "]}"
    WriteUtf8 outDir & "\" & fso.GetBaseName(f.Name) & ".json", out
    If Len(skipped) > 0 Then
        WriteUtf8 outDir & "\" & fso.GetBaseName(f.Name) & ".skipped.txt", skipped
    End If
End Sub

Private Function EvalCase(ws As Worksheet, id As String, formula As String, _
                          grid As String, nowMode As String, tags As String, _
                          iterSpec As String, namesSpec As String, _
                          ByRef skipReason As String) As String
    ws.Cells.Clear
    ' Optional 6th spec column "N:C": enable Excel iterative calculation for
    ' this case only; settings are restored immediately after the read.
    Dim iterOn As Boolean, iterJson As String
    Dim oldIter As Boolean, oldMaxIter As Long, oldMaxChange As Double, oldAlerts As Boolean
    Dim iterChanged As Boolean
    iterOn = (Len(iterSpec) > 0)
    iterJson = ""
    iterChanged = False
    oldIter = False
    oldMaxIter = 100
    oldMaxChange = 0.001
    oldAlerts = True
    ' Everything this case adds to the workbook: extra worksheets from grid
    ' keys (normalized name -> Worksheet) and workbook names (normalized name ->
    ' name as written). CleanupCase undoes both on every exit path. The
    ' dictionaries are late-bound; no VBA reference is required.
    Dim extra As Object, added As Object
    Set extra = CreateObject("Scripting.Dictionary")
    Set added = CreateObject("Scripting.Dictionary")
    Dim reason As String, expected As String
    Dim nowJson As String, namesField As String
    Dim ok As Boolean
    reason = ""
    expected = ""
    nowJson = ""
    namesField = ""
    ok = False
    On Error GoTo CaseFail

    ' The calculation settings are saved unconditionally: cases with an "N:C"
    ' column switch iteration on, every other case switches it off, so a
    ' circular-reference case without an iter column always observes Excel's
    ' default behaviour even if the workbook had iteration left enabled.
    oldIter = Application.Iteration
    oldMaxIter = Application.MaxIterations
    oldMaxChange = Application.MaxChange
    oldAlerts = Application.DisplayAlerts
    iterChanged = True
    Application.DisplayAlerts = False
    If iterOn Then
        Dim ip() As String
        ip = Split(iterSpec, ":")
        Application.Iteration = True
        Application.MaxIterations = CLng(ip(0))
        Application.MaxChange = CDbl(ip(1))
        iterJson = ",""iter"":{""max_iterations"":" & ip(0) & _
                   ",""max_change"":" & Replace(ip(1), ",", ".") & "}"
    ElseIf oldIter Then
        Application.Iteration = False
    End If

    reason = PrepareSheets(ws, grid, extra)
    ' Workbook-scoped names with an unqualified reference ($B$1) are bound to
    ' the sheet that is active when the name is created; activate the main
    ' temporary sheet so "names" specs can address it without knowing its
    ' random name.
    If Len(reason) = 0 Then
        ws.Activate
        reason = AddDefinedNames(namesSpec, added)
    End If
    If Len(reason) = 0 Then reason = WriteGridCells(ws, grid, extra)
    If Len(reason) > 0 Then GoTo CaseDone

    ws.Range("ZZ1").Formula = formula
    If nowMode = "capture" Then
        ' Capture the workbook clock at exactly the same recalc instant as the
        ' answer cell: a worksheet NOW() helper cell is evaluated in the same
        ' calculation pass (VBA's Now is truncated to whole seconds and cannot
        ' reproduce the serial that =NOW() returned).
        ws.Range("ZY1").Formula = "=NOW()"
    End If
    Application.Calculate
    If nowMode = "capture" Then
        nowJson = ",""now"":" & NumToJson(CDbl(ws.Range("ZY1").Value))
    End If
    Dim v As Variant
    v = ws.Range("ZZ1").Value
    If IsError(v) Then
        expected = "{""type"":""error"",""value"":""" & ErrName(v) & """}"
    ElseIf IsEmpty(v) Then
        expected = "{""type"":""blank"",""value"":null}"
    ElseIf VarType(v) = vbBoolean Then
        If v Then expected = "{""type"":""bool"",""value"":true}" Else expected = "{""type"":""bool"",""value"":false}"
    ElseIf VarType(v) = vbString Then
        expected = "{""type"":""text"",""value"":""" & JsonEsc(CStr(v)) & """}"
    Else
        expected = "{""type"":""number"",""value"":" & NumToJson(CDbl(v)) & "}"
    End If
    namesField = NamesJson(namesSpec)
    ok = True

CaseDone:
    On Error GoTo 0
    CleanupCase extra, added, iterChanged, oldIter, oldMaxIter, oldMaxChange, oldAlerts
    If Not ok Then
        skipReason = reason
        EvalCase = ""
        Exit Function
    End If
    EvalCase = "{""id"":""" & JsonEsc(id) & """,""formula"":""" & JsonEsc(formula) & _
               """,""grid"":" & GridJson(ws, grid) & nowJson & iterJson & namesField & _
               ",""expected"":" & expected & _
               ",""tags"":" & TagsJson(tags) & _
               ",""source"":""excel-desktop"",""notes"":""""}"
    Exit Function
CaseFail:
    reason = "excel-rejected: " & Sanitize(Err.Number & " " & Err.Description)
    ok = False
    Resume CaseDone
End Function

' Validate every grid key, create the worksheets it references on demand and
' reject the whole case when a key or a sheet name is unusable. Returns "" on
' success, otherwise the reason (the case is skipped and the run continues).
Private Function PrepareSheets(ws As Worksheet, grid As String, extra As Object) As String
    Dim cells() As String, i As Long, seen As Object
    Dim cell As String, eq As Long, addr As String
    Dim shName As String, a1 As String, norm As String, shKey As String
    Dim shNew As Worksheet
    PrepareSheets = ""
    If Len(grid) = 0 Then Exit Function
    Set seen = CreateObject("Scripting.Dictionary")
    cells = Split(grid, "|")
    For i = 0 To UBound(cells)
        cell = cells(i)
        eq = InStr(cell, "=")
        If eq = 0 Then
            PrepareSheets = "malformed grid cell (no '='): " & cell
            Exit Function
        End If
        addr = Left(cell, eq - 1)
        If Not SplitAddr(addr, shName, a1) Then
            PrepareSheets = "bad grid address: " & addr
            Exit Function
        End If
        If Not NormKey(ws, addr, norm) Then
            PrepareSheets = "bad grid address: " & addr
            Exit Function
        End If
        If seen.Exists(norm) Then
            PrepareSheets = "duplicate grid address after normalization: " & norm
            Exit Function
        End If
        seen.Add norm, True
        If Len(shName) > 0 Then
            shKey = AsciiUpper(shName)
            If shKey <> AsciiUpper(ws.Name) And Not extra.Exists(shKey) Then
                PrepareSheets = SheetNameProblem(shName)
                If Len(PrepareSheets) > 0 Then Exit Function
                If SheetExistsByName(shKey) Then
                    PrepareSheets = "worksheet already exists in workbook: " & shName
                    Exit Function
                End If
                Set shNew = ThisWorkbook.Worksheets.Add
                On Error Resume Next
                Err.Clear
                shNew.Name = shName
                If Err.Number <> 0 Then
                    Err.Clear
                    On Error GoTo 0
                    DeleteSheet shNew
                    PrepareSheets = "worksheet name rejected by Excel: " & shName
                    Exit Function
                End If
                On Error GoTo 0
                extra.Add shKey, shNew
            End If
        End If
    Next i
End Function

Private Function WriteGridCells(ws As Worksheet, grid As String, extra As Object) As String
    Dim cells() As String, i As Long
    Dim cell As String, eq As Long, addr As String, spec As String
    Dim shName As String, a1 As String, shKey As String
    Dim target As Worksheet
    WriteGridCells = ""
    If Len(grid) = 0 Then Exit Function
    cells = Split(grid, "|")
    For i = 0 To UBound(cells)
        cell = cells(i)
        eq = InStr(cell, "=")
        addr = Left(cell, eq - 1)
        spec = Mid(cell, eq + 1)
        If Not SplitAddr(addr, shName, a1) Then
            WriteGridCells = "bad grid address: " & addr
            Exit Function
        End If
        Set target = ws
        If Len(shName) > 0 Then
            shKey = AsciiUpper(shName)
            If shKey <> AsciiUpper(ws.Name) Then
                Set target = extra(shKey)
            End If
        End If
        WriteCell target, a1, spec
    Next i
End Function

' Optional 7th spec column "Name1=Ref1|Name2=Ref2". Names are workbook scoped
' and removed again by CleanupCase once the answer has been read. Excel names
' are case-insensitive, so an existing name with the same spelling (any case)
' is deleted before the case name is added.
Private Function AddDefinedNames(namesSpec As String, added As Object) As String
    Dim parts() As String, i As Long
    Dim item As String, eq As Long, nm As String, refText As String, nmKey As String
    AddDefinedNames = ""
    If Len(namesSpec) = 0 Then Exit Function
    parts = Split(namesSpec, "|")
    For i = 0 To UBound(parts)
        item = Trim(parts(i))
        If Len(item) = 0 Then
            AddDefinedNames = "empty defined-name entry"
            Exit Function
        End If
        eq = InStr(item, "=")
        If eq = 0 Then
            AddDefinedNames = "malformed defined-name entry: " & item
            Exit Function
        End If
        nm = Trim(Left(item, eq - 1))
        refText = CleanRef(Mid(item, eq + 1))
        If Len(refText) = 0 Then
            AddDefinedNames = "empty defined-name reference: " & nm
            Exit Function
        End If
        If Not IsValidName(nm) Then
            AddDefinedNames = "illegal defined name: " & nm
            Exit Function
        End If
        nmKey = AsciiUpper(nm)
        If added.Exists(nmKey) Then
            AddDefinedNames = "duplicate defined name: " & nm
            Exit Function
        End If
        DeleteWorkbookName nmKey
        On Error Resume Next
        Err.Clear
        ThisWorkbook.Names.Add Name:=nm, RefersTo:="=" & refText
        If Err.Number <> 0 Then
            Err.Clear
            On Error GoTo 0
            AddDefinedNames = "Excel rejected defined name: " & nm
            Exit Function
        End If
        On Error GoTo 0
        added.Add nmKey, nm
    Next i
End Function

' Undo everything one case added: iteration/alert settings, workbook names and
' every worksheet created from its grid keys. Tolerates partial setup.
Private Sub CleanupCase(extra As Object, added As Object, _
                        iterChanged As Boolean, oldIter As Boolean, _
                        oldMaxIter As Long, oldMaxChange As Double, oldAlerts As Boolean)
    Dim k As Variant
    Dim sh As Worksheet
    On Error Resume Next
    If iterChanged Then
        Application.Iteration = oldIter
        Application.MaxIterations = oldMaxIter
        Application.MaxChange = oldMaxChange
        Application.DisplayAlerts = oldAlerts
    End If
    For Each k In added.Keys
        DeleteWorkbookName CStr(k)
    Next k
    added.RemoveAll
    For Each k In extra.Keys
        Set sh = extra(k)
        DeleteSheet sh
    Next k
    extra.RemoveAll
    Err.Clear
End Sub

Private Sub DeleteSheet(sh As Worksheet)
    Dim oldAlerts As Boolean
    If sh Is Nothing Then Exit Sub
    oldAlerts = Application.DisplayAlerts
    Application.DisplayAlerts = False
    On Error Resume Next
    sh.Delete
    Err.Clear
    Application.DisplayAlerts = oldAlerts
End Sub

Private Sub DeleteWorkbookName(nmKey As String)
    Dim i As Long, nm As Name
    On Error Resume Next
    For i = ThisWorkbook.Names.Count To 1 Step -1
        Set nm = ThisWorkbook.Names(i)
        If Not nm Is Nothing Then
            If AsciiUpper(nm.Name) = nmKey Then nm.Delete
        End If
        Set nm = Nothing
    Next i
    Err.Clear
End Sub

' Split a grid key on the LAST "!" into sheet name + A1 address. A bare
' address (no "!") belongs to the main temporary sheet (sheet name "").
' A quoted sheet part ('My Sheet', 'O''Brien') is unquoted here, so a spec may
' spell a grid key the way Excel spells a reference; the JSON key is then
' normalized to the unquoted, ASCII-upper form.
Private Function SplitAddr(raw As String, ByRef sheetName As String, ByRef a1 As String) As Boolean
    Dim p As Long
    sheetName = ""
    a1 = ""
    SplitAddr = False
    p = InStrRev(raw, "!")
    If p > 0 Then
        sheetName = Left(raw, p - 1)
        a1 = Mid(raw, p + 1)
        If Len(sheetName) = 0 Then Exit Function
        If Len(sheetName) >= 2 Then
            If Left(sheetName, 1) = "'" And Right(sheetName, 1) = "'" Then
                sheetName = Replace(Mid(sheetName, 2, Len(sheetName) - 2), "''", "'")
                If Len(sheetName) = 0 Then Exit Function
            End If
        End If
    Else
        a1 = raw
    End If
    SplitAddr = IsA1(a1)
End Function

' Column letters followed by row digits (A1 .. XFD1048576 shape).
Private Function IsA1(ByVal s As String) As Boolean
    Dim i As Long, code As Long, seenDigit As Boolean
    IsA1 = False
    If Len(s) = 0 Or Len(s) > 16 Then Exit Function
    seenDigit = False
    For i = 1 To Len(s)
        code = AscW(Mid(s, i, 1))
        If code >= 65 And code <= 90 Then
            If seenDigit Then Exit Function
        ElseIf code >= 97 And code <= 122 Then
            If seenDigit Then Exit Function
        ElseIf code >= 48 And code <= 57 Then
            If i = 1 Then Exit Function
            seenDigit = True
        Else
            Exit Function
        End If
    Next i
    IsA1 = seenDigit
End Function

' Normalize a grid key for the JSON record: bare "A1" when it belongs to the
' main temporary sheet (bare key or the main sheet's own name), else
' "SHEET!A1". The sheet part is ASCII-only upper case (VBA UCase folds
' according to the system locale, which would corrupt non-ASCII sheet names)
' and the A1 part is upper-cased as well.
Private Function NormKey(ws As Worksheet, raw As String, ByRef norm As String) As Boolean
    Dim shName As String, a1 As String
    norm = ""
    NormKey = False
    If Not SplitAddr(raw, shName, a1) Then Exit Function
    a1 = AsciiUpper(a1)
    If Len(shName) = 0 Then
        norm = a1
    ElseIf AsciiUpper(shName) = AsciiUpper(ws.Name) Then
        norm = a1
    Else
        norm = AsciiUpper(shName) & "!" & a1
    End If
    NormKey = True
End Function

' ASCII-only upper case: leaves non-ASCII characters untouched, independent of
' the system locale.
Private Function AsciiUpper(ByVal s As String) As String
    Dim i As Long, code As Long, ch As String, out As String
    out = ""
    For i = 1 To Len(s)
        ch = Mid(s, i, 1)
        code = AscW(ch)
        If code >= 97 And code <= 122 Then
            out = out & Chr(code - 32)
        Else
            out = out & ch
        End If
    Next i
    AsciiUpper = out
End Function

' Excel worksheet-name rules used by the corpus: 1..31 characters, none of
' : \ / ? * [ ] !, no control character, no leading/trailing apostrophe.
' Returns "" when the name is usable, otherwise the reason.
Private Function SheetNameProblem(ByVal n As String) As String
    Dim i As Long, ch As String, code As Long
    SheetNameProblem = ""
    If Len(n) = 0 Then
        SheetNameProblem = "empty sheet name"
        Exit Function
    End If
    If Len(n) > 31 Then
        SheetNameProblem = "sheet name longer than 31 chars: " & n
        Exit Function
    End If
    For i = 1 To Len(n)
        ch = Mid(n, i, 1)
        code = AscW(ch)
        If code < 32 Then
            SheetNameProblem = "control character in sheet name"
            Exit Function
        End If
        Select Case ch
            Case ":", "\", "/", "?", "*", "[", "]", "!"
                SheetNameProblem = "illegal character in sheet name: " & n
                Exit Function
        End Select
    Next i
    If Left(n, 1) = "'" Or Right(n, 1) = "'" Then
        SheetNameProblem = "sheet name starts or ends with apostrophe: " & n
        Exit Function
    End If
End Function

Private Function SheetExistsByName(ByVal nmKey As String) As Boolean
    Dim s As Worksheet
    SheetExistsByName = False
    For Each s In ThisWorkbook.Worksheets
        If AsciiUpper(s.Name) = nmKey Then
            SheetExistsByName = True
            Exit Function
        End If
    Next s
End Function

Private Function FreeTempSheetName() As String
    Dim nm As String, n As Long
    nm = "MC_Temp_" & Format(Now, "hhmmss")
    Do While SheetExistsByName(AsciiUpper(nm))
        n = n + 1
        nm = "MC_Temp_" & Format(Now, "hhmmss") & "_" & n
    Loop
    FreeTempSheetName = nm
End Function

' Excel defined-name rules used by the corpus: [A-Za-z_][A-Za-z0-9_]*, and not
' a cell-reference-like token (A1, AB12) or an R/C reference token (R, C, RC,
' R1C1, ...).
Private Function IsValidName(ByVal n As String) As Boolean
    Dim i As Long
    IsValidName = False
    If Len(n) = 0 Or Len(n) > 255 Then Exit Function
    If Not IsNameStartChar(AscW(Left(n, 1))) Then Exit Function
    For i = 2 To Len(n)
        If Not IsNameChar(AscW(Mid(n, i, 1))) Then Exit Function
    Next i
    If IsCellRefLike(n) Then Exit Function
    IsValidName = True
End Function

Private Function IsNameStartChar(ByVal code As Long) As Boolean
    IsNameStartChar = (code >= 65 And code <= 90) Or (code >= 97 And code <= 122) Or code = 95
End Function

Private Function IsNameChar(ByVal code As Long) As Boolean
    IsNameChar = IsNameStartChar(code) Or (code >= 48 And code <= 57)
End Function

Private Function IsCellRefLike(ByVal n As String) As Boolean
    Dim i As Long, code As Long, u As String, hasDigit As Boolean
    IsCellRefLike = False
    u = AsciiUpper(n)
    ' A1 style: one or more letters followed by one or more digits.
    hasDigit = False
    i = 1
    Do While i <= Len(u)
        code = AscW(Mid(u, i, 1))
        If code >= 65 And code <= 90 Then
            If hasDigit Then Exit Do
        ElseIf code >= 48 And code <= 57 Then
            hasDigit = True
        Else
            Exit Do
        End If
        i = i + 1
    Loop
    If hasDigit And i > Len(u) Then
        IsCellRefLike = True
        Exit Function
    End If
    ' R1C1 style: R and C separated only by digits (R, C, RC, R1C1, R1C).
    If IsRcLike(u) Then IsCellRefLike = True
End Function

Private Function IsRcLike(ByVal u As String) As Boolean
    Dim i As Long
    IsRcLike = False
    If Len(u) = 0 Then Exit Function
    If Left(u, 1) = "C" Then
        IsRcLike = AllDigits(Mid(u, 2))
        Exit Function
    End If
    If Left(u, 1) <> "R" Then Exit Function
    i = 2
    Do While i <= Len(u)
        If Not IsDigitChar(AscW(Mid(u, i, 1))) Then Exit Do
        i = i + 1
    Loop
    If i > Len(u) Then
        IsRcLike = True
        Exit Function
    End If
    If Mid(u, i, 1) <> "C" Then Exit Function
    IsRcLike = AllDigits(Mid(u, i + 1))
End Function

Private Function AllDigits(ByVal s As String) As Boolean
    Dim i As Long
    AllDigits = True
    For i = 1 To Len(s)
        If Not IsDigitChar(AscW(Mid(s, i, 1))) Then
            AllDigits = False
            Exit Function
        End If
    Next i
End Function

Private Function IsDigitChar(ByVal code As Long) As Boolean
    IsDigitChar = (code >= 48 And code <= 57)
End Function

' "=Ref" as written in the spec, without surrounding blanks and without a
' redundant leading "=".
Private Function CleanRef(ByVal s As String) As String
    Dim t As String
    t = Trim(s)
    If Left(t, 1) = "=" Then t = Trim(Mid(t, 2))
    CleanRef = t
End Function

Private Function Sanitize(ByVal s As String) As String
    Dim t As String
    t = Replace(s, vbCr, " ")
    t = Replace(t, vbLf, " ")
    t = Replace(t, vbTab, " ")
    Sanitize = t
End Function

Private Sub WriteCell(ws As Worksheet, addr As String, spec As String)
    Dim r As Range
    Set r = ws.Range(addr)
    If spec = "blank" Then
        ' leave empty
    ElseIf Left(spec, 2) = "t:" Then
        r.NumberFormat = "@"
        r.Value = Mid(spec, 3)
    ElseIf Left(spec, 2) = "b:" Then
        r.Value = (Mid(spec, 3) = "1")
    ElseIf Left(spec, 2) = "e:" Then
        r.Value = CVErr(ErrCode(Mid(spec, 3)))
    ElseIf Left(spec, 2) = "f:" Then
        r.Formula = Mid(spec, 3)
    Else
        r.NumberFormat = "General"
        r.Value = Val(spec)
    End If
End Sub

Private Function GridJson(ws As Worksheet, grid As String) As String
    Dim out As String, first As Boolean
    out = "{"
    first = True
    If Len(grid) > 0 Then
        Dim cells() As String, i As Long
        cells = Split(grid, "|")
        For i = 0 To UBound(cells)
            Dim cell As String, eq As Long, addr As String, spec As String, v As String
            Dim norm As String
            cell = cells(i)
            eq = InStr(cell, "=")
            If eq > 0 Then
                addr = Left(cell, eq - 1)
                spec = Mid(cell, eq + 1)
                If Not NormKey(ws, addr, norm) Then norm = addr
                If spec = "blank" Then
                    v = "null"
                ElseIf Left(spec, 2) = "t:" Then
                    v = """" & JsonEsc(Mid(spec, 3)) & """"
                ElseIf Left(spec, 2) = "b:" Then
                    If Mid(spec, 3) = "1" Then v = "true" Else v = "false"
                ElseIf Left(spec, 2) = "e:" Then
                    v = "{""error"":""" & Mid(spec, 3) & """}"
                ElseIf Left(spec, 2) = "f:" Then
                    v = "{""formula"":""" & JsonEsc(Mid(spec, 3)) & """}"
                Else
                    v = NumToJson(Val(spec))
                End If
                If Not first Then out = out & ","
                out = out & """" & JsonEsc(norm) & """:" & v
                first = False
            End If
        Next i
    End If
    GridJson = out & "}"
End Function

' Optional "names" record field: {"NAME":"Ref",...} with ASCII-upper name keys.
' Emitted only for cases that declare names; includes the leading comma.
Private Function NamesJson(namesSpec As String) As String
    Dim out As String, first As Boolean, parts() As String, i As Long
    Dim item As String, eq As Long
    NamesJson = ""
    If Len(namesSpec) = 0 Then Exit Function
    out = ",""names"":{
    first = True
    parts = Split(namesSpec, "|")
    For i = 0 To UBound(parts)
        item = Trim(parts(i))
        eq = InStr(item, "=")
        If eq > 0 Then
            If Not first Then out = out & ","
            out = out & """" & JsonEsc(AsciiUpper(Trim(Left(item, eq - 1)))) & """:""" & _
                  JsonEsc(CleanRef(Mid(item, eq + 1))) & """"
            first = False
        End If
    Next i
    NamesJson = out & "}"
End Function

Private Function TagsJson(tags As String) As String
    Dim out As String, parts() As String, i As Long
    out = "["
    parts = Split(tags, ",")
    For i = 0 To UBound(parts)
        If i > 0 Then out = out & ","
        out = out & """" & JsonEsc(Trim(parts(i))) & """"
    Next i
    TagsJson = out & "]"
End Function

Private Function ErrCode(name As String) As Long
    Select Case name
        Case "#DIV/0!": ErrCode = 2007
        Case "#N/A": ErrCode = 2042
        Case "#NAME?": ErrCode = 2029
        Case "#NULL!": ErrCode = 2000
        Case "#NUM!": ErrCode = 2036
        Case "#REF!": ErrCode = 2023
        Case "#VALUE!": ErrCode = 2015
        Case Else: ErrCode = 2015
    End Select
End Function

Private Function ErrName(e As Variant) As String
    Select Case CLng(e)
        Case 2007: ErrName = "#DIV/0!"
        Case 2042: ErrName = "#N/A"
        Case 2029: ErrName = "#NAME?"
        Case 2000: ErrName = "#NULL!"
        Case 2036: ErrName = "#NUM!"
        Case 2023: ErrName = "#REF!"
        Case 2015: ErrName = "#VALUE!"
        ' #CALC! is the Excel 365 dynamic-array calculation error (VBA 2050),
        ' e.g. TEXTJOIN producing more than 32767 characters.
        Case 2050: ErrName = "#CALC!"
        Case Else: ErrName = "#UNKNOWN(" & CLng(e) & ")"
    End Select
End Function

Private Function NumToJson(d As Double) As String
    NumToJson = Replace(CStr(d), ",", ".")
End Function

Private Function JsonEsc(s As String) As String
    Dim out As String
    out = Replace(s, "\", "\\")
    out = Replace(out, """", "\""")
    out = Replace(out, vbCr, "\r")
    out = Replace(out, vbLf, "\n")
    out = Replace(out, vbTab, "\t")
    JsonEsc = out
End Function

Private Function ReadUtf8(path As String) As String
    Dim st As Object
    Set st = CreateObject("ADODB.Stream")
    st.Type = 2
    st.Charset = "utf-8"
    st.Open
    st.LoadFromFile path
    ReadUtf8 = st.ReadText
    st.Close
End Function

Private Sub WriteUtf8(path As String, content As String)
    Dim st As Object
    Set st = CreateObject("ADODB.Stream")
    st.Type = 2
    st.Charset = "utf-8"
    st.Open
    st.WriteText content
    st.SaveToFile path, 2
    st.Close
End Sub
