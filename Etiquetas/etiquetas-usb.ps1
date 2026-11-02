# 1. Configuracion
# Nombre EXACTO de la impresora tal como figura en "Impresoras y escaneres"
# Obtenelo con: Get-Printer | Select-Object Name, PortName
$printerName = "ZDesigner ZD230-203dpi ZPL"   # nombre confirmado con Get-Printer
$templatePath = "C:\Users\Asus\Desktop\scripts\Etiqueta_nueva.prn"

# 2. Valor dinamico a imprimir
$barras = "0788"

# ============================================================
# Funcion auxiliar: envia bytes crudos (RAW) directo al spooler
# Esto evita que Windows intente "traducir" el ZPL como si fuera
# texto normal - lo manda tal cual, como necesita la impresora.
# ============================================================
if (-not ("RawPrinterHelper" -as [type])) {
    Add-Type -Name RawPrinterHelper -Namespace PrintTools -MemberDefinition @"
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
public struct DOCINFOA {
    [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
}

[DllImport("winspool.drv", EntryPoint="OpenPrinterA", SetLastError=true, CharSet=CharSet.Ansi)]
public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);

[DllImport("winspool.drv", EntryPoint="ClosePrinter", SetLastError=true)]
public static extern bool ClosePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", EntryPoint="StartDocPrinterA", SetLastError=true, CharSet=CharSet.Ansi)]
public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] ref DOCINFOA di);

[DllImport("winspool.drv", EntryPoint="EndDocPrinter", SetLastError=true)]
public static extern bool EndDocPrinter(IntPtr hPrinter);

[DllImport("winspool.drv", EntryPoint="StartPagePrinter", SetLastError=true)]
public static extern bool StartPagePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", EntryPoint="EndPagePrinter", SetLastError=true)]
public static extern bool EndPagePrinter(IntPtr hPrinter);

[DllImport("winspool.drv", EntryPoint="WritePrinter", SetLastError=true)]
public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

public static bool SendBytesToPrinter(string szPrinterName, byte[] data, out int errorCode) {
    IntPtr hPrinter;
    DOCINFOA di = new DOCINFOA();
    di.pDocName = "Etiqueta ZPL";
    di.pDataType = "RAW";

    bool ok = OpenPrinter(szPrinterName, out hPrinter, IntPtr.Zero);
    if (!ok) { errorCode = Marshal.GetLastWin32Error(); return false; }

    ok = StartDocPrinter(hPrinter, 1, ref di);
    if (!ok) { errorCode = Marshal.GetLastWin32Error(); ClosePrinter(hPrinter); return false; }

    ok = StartPagePrinter(hPrinter);
    if (!ok) { errorCode = Marshal.GetLastWin32Error(); EndDocPrinter(hPrinter); ClosePrinter(hPrinter); return false; }

    IntPtr pUnmanagedBytes = Marshal.AllocCoTaskMem(data.Length);
    Marshal.Copy(data, 0, pUnmanagedBytes, data.Length);
    int written;
    ok = WritePrinter(hPrinter, pUnmanagedBytes, data.Length, out written);
    errorCode = ok ? 0 : Marshal.GetLastWin32Error();
    Marshal.FreeCoTaskMem(pUnmanagedBytes);

    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);
    return ok;
}
"@
}

# 3. Leer y armar el contenido ZPL (misma logica que antes)
$zplContent = Get-Content -Path $templatePath -Raw -Encoding UTF8

# Limpiar basura/BOM antes del ^XA
$inicio = $zplContent.IndexOf("^XA")
if ($inicio -gt 0) { $zplContent = $zplContent.Substring($inicio) }

# Quitar ^DFR (guardado de formato en vez de imprimir), por si aparece
$zplContent = $zplContent -replace "\^DFR:[^\^]*\^FS", ""

# Reemplazar el placeholder
$zplContent = $zplContent -replace "\{\{BARRAS\}\}", $barras

# 4. Enviar los bytes al spooler en modo RAW
$bytes = [System.Text.Encoding]::UTF8.GetBytes($zplContent)
$errorCode = 0
$ok = [PrintTools.RawPrinterHelper]::SendBytesToPrinter($printerName, $bytes, [ref]$errorCode)

if ($ok) {
    Write-Host "Etiqueta enviada con éxito a '$printerName'" -ForegroundColor Green
} else {
    Write-Host "No se pudo enviar la etiqueta. Código de error de Windows: $errorCode" -ForegroundColor Red
    if ($errorCode -ne 0) {
        $win32ex = New-Object System.ComponentModel.Win32Exception($errorCode)
        Write-Host "Detalle: $($win32ex.Message)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Impresoras disponibles en este equipo:" -ForegroundColor Cyan
    Get-Printer | Select-Object Name, PortName, PrinterStatus | Format-Table -AutoSize
}
