Attribute VB_Name = "MoonCalcCorpus"
Option Explicit

' MoonCalc answer-key corpus generator (desktop Excel).
' Reads corpus/spec/*.tsv (UTF-8), computes each case in real Excel,
' writes corpus/cases/<name>.json (schema mooncalc-corpus/1).
' Cases Excel rejects are skipped and logged to <name>.skipped.txt.

Sub GenerateCorpus()
    Dim fso As Object, base As String, specDir As String, outDir As String
    Set fso = CreateObject("Scripting.FileSystemObject")
    base = ThisWorkbook.Path
    specDir = base & "\..\spec"
    outDir = base & "\..\cases"
    If Not fso.FolderExists(specDir) Then
        MsgBox "spec dir not found: " & specDir
        Exit Sub
    End If
    If Not fso.FolderExists(outDir) Then fso.CreateFolder outDir

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Worksheets.Add
    ws.Name = "MC_Temp_" & Format(Now, "hhmmss")

    Dim oldCalc As XlCalculation
    oldCalc = Application.Calculation
    Application.Calculation = xlCalculationManual
    Application.ScreenUpdating = False
    On Error GoTo Cleanup

    Dim f As Object, count As Long
    count = 0
    For Each f In fso.GetFolder(specDir).Files
        If LCase(fso.GetExtensionName(f.Name)) = "tsv" Then
            ProcessSpec fso, f, ws, outDir
            count = count + 1
        End If
    Next f

Cleanup:
    Application.Calculation = oldCalc
    Application.ScreenUpdating = True
    Application.DisplayAlerts = False
    ws.Delete
    Application.DisplayAlerts = True
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
                rec = EvalCase(ws, parts(0), parts(1), parts(2), parts(3), parts(4))
                If Len(rec) = 0 Then
                    skipped = skipped & parts(0) & vbLf
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
                          grid As String, nowMode As String, tags As String) As String
    ws.Cells.Clear
    On Error Resume Next
    If Len(grid) > 0 Then
        Dim cells() As String, i As Long
        cells = Split(grid, "|")
        For i = 0 To UBound(cells)
            Dim cell As String, eq As Long, addr As String, spec As String
            cell = cells(i)
            eq = InStr(cell, "=")
            If eq > 0 Then
                addr = Left(cell, eq - 1)
                spec = Mid(cell, eq + 1)
                WriteCell ws, addr, spec
            End If
        Next i
    End If
    ws.Range("ZZ1").Formula = formula
    If Err.Number <> 0 Then
        ' Excel rejected the formula or a grid cell: skip, do not abort the run.
        Err.Clear
        On Error GoTo 0
        EvalCase = ""
        Exit Function
    End If
    On Error GoTo 0
    Application.Calculate
    Dim nowJson As String
    nowJson = ""
    If nowMode = "capture" Then
        nowJson = ",""now"":" & NumToJson(CDbl(Now))
    End If
    Dim v As Variant, expected As String
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
        expected = "{""type"":""number"",""value":":" & NumToJson(CDbl(v)) & "}"
    End If
    EvalCase = "{""id"":""" & JsonEsc(id) & """,""formula"":""" & JsonEsc(formula) & _
               """,""grid"":" & GridJson(grid) & nowJson & _
               ",""expected"":" & expected & _
               ",""tags"":" & TagsJson(tags) & _
               ",""source"":""excel-desktop"",""notes"":""""}"
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

Private Function GridJson(grid As String) As String
    Dim out As String, first As Boolean
    out = "{"
    first = True
    If Len(grid) > 0 Then
        Dim cells() As String, i As Long
        cells = Split(grid, "|")
        For i = 0 To UBound(cells)
            Dim cell As String, eq As Long, addr As String, spec As String, v As String
            cell = cells(i)
            eq = InStr(cell, "=")
            If eq > 0 Then
                addr = Left(cell, eq - 1)
                spec = Mid(cell, eq + 1)
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
                out = out & """" & addr & """:" & v
                first = False
            End If
        Next i
    End If
    GridJson = out & "}"
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