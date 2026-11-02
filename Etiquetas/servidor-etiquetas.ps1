# ============================================================
# Servidor local para imprimir etiquetas desde una pagina HTML
# Corre este script (como Administrador) y despues abri en el
# navegador: http://localhost:8080
# Para cortarlo: Ctrl + C en la ventana de PowerShell
# ============================================================

# 1. Configuracion
$printerName  = "ZDesigner ZD230-203dpi ZPL"
$templatePath = "C:\Users\Asus\Desktop\scripts\Etiqueta_nueva.prn"
$puerto       = 8080

# ============================================================
# Funcion auxiliar: envia bytes crudos (RAW) directo al spooler
# ============================================================
if (-not ("PrintTools.RawPrinterHelper" -as [type])) {
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

function Imprimir-Etiqueta {
    param([string]$Texto)

    $zplContent = Get-Content -Path $templatePath -Raw -Encoding UTF8

    $inicio = $zplContent.IndexOf("^XA")
    if ($inicio -gt 0) { $zplContent = $zplContent.Substring($inicio) }

    $zplContent = $zplContent -replace "\^DFR:[^\^]*\^FS", ""
    $zplContent = $zplContent -replace "\{\{BARRAS\}\}", $Texto

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($zplContent)
    $errorCode = 0
    $ok = [PrintTools.RawPrinterHelper]::SendBytesToPrinter($printerName, $bytes, [ref]$errorCode)
    return @{ ok = $ok; errorCode = $errorCode }
}

# ============================================================
# Pagina HTML servida en "/"
# ============================================================
$paginaHtml = @"
<!DOCTYPE html>
<html lang='es'>
<head>
<meta charset='UTF-8'>
<title>Imprimir etiqueta</title>
<style>
  body { font-family: Arial, sans-serif; max-width: 420px; margin: 40px auto; padding: 0 16px; }
  h1 { font-size: 20px; }
  input { width: 100%; padding: 10px; font-size: 16px; box-sizing: border-box; margin-bottom: 12px; }
  label { font-size: 13px; color: #555; display: block; margin-bottom: 4px; }
  .fila { display: flex; gap: 10px; }
  .fila > div { flex: 1; }
  .modos { display: flex; gap: 10px; margin-bottom: 16px; }
  .modos label { display: flex; align-items: center; gap: 6px; font-size: 14px; color: #333; }
  button { width: 100%; padding: 12px; font-size: 16px; background: #2563eb; color: white; border: none; border-radius: 6px; cursor: pointer; }
  button:disabled { background: #999; }
  #resultado { margin-top: 16px; font-size: 14px; white-space: pre-line; }
  .ok { color: #16a34a; }
  .error { color: #dc2626; }
  .oculto { display: none; }
</style>
</head>
<body>
  <h1>Imprimir etiqueta</h1>

  <div class='modos'>
    <label><input type='radio' name='modo' value='texto' checked onchange='cambiarModo()'> Texto</label>
    <label><input type='radio' name='modo' value='rango' onchange='cambiarModo()'> Rango numerado</label>
  </div>

  <div id='bloqueTexto'>
    <label for='barras'>Texto a imprimir</label>
    <input type='text' id='barras' placeholder='Ej: Compra Coca'>
    <label for='copiasTexto'>Cantidad de copias</label>
    <input type='number' id='copiasTexto' value='1' min='1'>
  </div>

  <div id='bloqueRango' class='oculto'>
    <div class='fila'>
      <div>
        <label for='desde'>Desde</label>
        <input type='number' id='desde' placeholder='300'>
      </div>
      <div>
        <label for='hasta'>Hasta</label>
        <input type='number' id='hasta' placeholder='320'>
      </div>
    </div>
    <label for='copiasRango'>Copias de cada número</label>
    <input type='number' id='copiasRango' value='1' min='1'>
  </div>

  <button id='btnImprimir' onclick='imprimir()'>Imprimir</button>
  <div id='resultado'></div>

<script>
function cambiarModo() {
  const modo = document.querySelector('input[name=modo]:checked').value;
  document.getElementById('bloqueTexto').classList.toggle('oculto', modo !== 'texto');
  document.getElementById('bloqueRango').classList.toggle('oculto', modo !== 'rango');
  document.getElementById('resultado').innerHTML = '';
}

async function imprimir() {
  const modo = document.querySelector('input[name=modo]:checked').value;
  const resultado = document.getElementById('resultado');
  const boton = document.getElementById('btnImprimir');
  let payload;

  if (modo === 'texto') {
    const texto = document.getElementById('barras').value.trim();
    const copias = parseInt(document.getElementById('copiasTexto').value, 10) || 1;
    if (!texto) {
      resultado.innerHTML = '<span class="error">Escribi un texto antes de imprimir.</span>';
      return;
    }
    payload = { modo: 'texto', texto: texto, copias: copias };
  } else {
    const desde = parseInt(document.getElementById('desde').value, 10);
    const hasta = parseInt(document.getElementById('hasta').value, 10);
    const copiasRango = parseInt(document.getElementById('copiasRango').value, 10) || 1;
    if (isNaN(desde) || isNaN(hasta)) {
      resultado.innerHTML = '<span class="error">Completa Desde y Hasta.</span>';
      return;
    }
    if (desde > hasta) {
      resultado.innerHTML = '<span class="error">Desde no puede ser mayor que Hasta.</span>';
      return;
    }
    payload = { modo: 'rango', desde: desde, hasta: hasta, copiasPorNumero: copiasRango };
  }

  boton.disabled = true;
  boton.textContent = 'Imprimiendo...';
  resultado.innerHTML = '';

  try {
    const resp = await fetch('/imprimir', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await resp.json();

    if (data.ok) {
      resultado.innerHTML = '<span class="ok">' + data.mensaje + '</span>';
      if (modo === 'texto') {
        document.getElementById('barras').value = '';
        document.getElementById('barras').focus();
      }
    } else {
      resultado.innerHTML = '<span class="error">Error: ' + data.mensaje + '</span>';
    }
  } catch (e) {
    resultado.innerHTML = '<span class="error">No se pudo conectar con el servidor local.</span>';
  } finally {
    boton.disabled = false;
    boton.textContent = 'Imprimir';
  }
}

document.getElementById('barras').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') imprimir();
});
</script>
</body>
</html>
"@

# ============================================================
# Servidor HTTP local
# ============================================================
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$puerto/")

try {
    $listener.Start()
}
catch {
    Write-Host "No se pudo iniciar el servidor en el puerto $puerto." -ForegroundColor Red
    Write-Host "Probablemente necesites correr esta ventana de PowerShell como Administrador." -ForegroundColor Yellow
    exit 1
}

Write-Host "Servidor corriendo. Abri en el navegador: http://localhost:$puerto" -ForegroundColor Green
Write-Host "Para cortar el servidor: Ctrl + C" -ForegroundColor Cyan

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
        if ($request.HttpMethod -eq "GET" -and $request.Url.LocalPath -eq "/") {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($paginaHtml)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/imprimir") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $json = $body | ConvertFrom-Json

            $total = 0
            $exitosas = 0
            $errores = @()

            if ($json.modo -eq "texto") {
                $texto = $json.texto
                $copias = [int]$json.copias
                if ($copias -lt 1) { $copias = 1 }

                Write-Host "Imprimiendo '$texto' x$copias copias" -ForegroundColor Cyan
                for ($i = 1; $i -le $copias; $i++) {
                    $total++
                    $resultado = Imprimir-Etiqueta -Texto $texto
                    if ($resultado.ok) {
                        $exitosas++
                    } else {
                        $win32ex = New-Object System.ComponentModel.Win32Exception($resultado.errorCode)
                        $errores += $win32ex.Message
                    }
                    Start-Sleep -Milliseconds 300
                }
            }
            elseif ($json.modo -eq "rango") {
                $desde = [int]$json.desde
                $hasta = [int]$json.hasta
                $copiasPorNumero = [int]$json.copiasPorNumero
                if ($copiasPorNumero -lt 1) { $copiasPorNumero = 1 }

                Write-Host "Imprimiendo rango $desde-$hasta x$copiasPorNumero copias c/u" -ForegroundColor Cyan
                for ($num = $desde; $num -le $hasta; $num++) {
                    for ($i = 1; $i -le $copiasPorNumero; $i++) {
                        $total++
                        $resultado = Imprimir-Etiqueta -Texto "$num"
                        if ($resultado.ok) {
                            $exitosas++
                        } else {
                            $win32ex = New-Object System.ComponentModel.Win32Exception($resultado.errorCode)
                            $errores += "Numero ${num}: $($win32ex.Message)"
                        }
                        Start-Sleep -Milliseconds 300
                    }
                }
            }
            else {
                $exitosas = 0
                $total = 0
                $respuestaJson = @{ ok = $false; mensaje = "Modo no reconocido" } | ConvertTo-Json
            }

            if ($json.modo -eq "texto" -or $json.modo -eq "rango") {
                if ($exitosas -eq $total) {
                    $mensaje = "Se imprimieron $exitosas de $total etiquetas correctamente."
                    $respuestaJson = @{ ok = $true; mensaje = $mensaje } | ConvertTo-Json
                    Write-Host "  -> OK ($exitosas/$total)" -ForegroundColor Green
                } else {
                    $mensaje = "Se imprimieron $exitosas de $total. Errores: " + ($errores -join "; ")
                    $respuestaJson = @{ ok = $false; mensaje = $mensaje } | ConvertTo-Json
                    Write-Host "  -> PARCIAL ($exitosas/$total)" -ForegroundColor Yellow
                }
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes($respuestaJson)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        else {
            $response.StatusCode = 404
        }
    }
    catch {
        Write-Host "Error procesando la solicitud: $($_.Exception.Message)" -ForegroundColor Red
        $response.StatusCode = 500
    }
    finally {
        $response.OutputStream.Close()
    }
}
