' Starts Fumefy (start.ps1) without showing a console window. The shortcuts point here;
' the Windows sign-in entry adds /startup so Spotify opens minimized.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
extra = ""
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "/startup" Then extra = " -Startup"
End If
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\start.ps1""" & extra, 0, False
