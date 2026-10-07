$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $root 'Source'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

[ComImport,Guid("8BA5FB08-5195-40E2-AC58-0D989C3A0102"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ID3DBlob {
    [PreserveSig] IntPtr GetBufferPointer();
    [PreserveSig] UIntPtr GetBufferSize();
}

public static class RdcShaderCompiler {
    [DllImport("d3dcompiler_47.dll",CharSet=CharSet.Ansi,CallingConvention=CallingConvention.Winapi)]
    static extern int D3DCompile(
        [MarshalAs(UnmanagedType.LPStr)] string srcData,
        UIntPtr srcDataSize,
        [MarshalAs(UnmanagedType.LPStr)] string sourceName,
        IntPtr defines,
        IntPtr include,
        [MarshalAs(UnmanagedType.LPStr)] string entryPoint,
        [MarshalAs(UnmanagedType.LPStr)] string target,
        uint flags1,
        uint flags2,
        out ID3DBlob code,
        out ID3DBlob errors);

    public static void Compile(string input,string output) {
        string src=File.ReadAllText(input,Encoding.UTF8);
        ID3DBlob code=null,errors=null;
        int hr=D3DCompile(
            src,
            new UIntPtr((uint)Encoding.ASCII.GetByteCount(src)),
            input,
            IntPtr.Zero,
            IntPtr.Zero,
            "main",
            "ps_3_0",
            0x8000,
            0,
            out code,
            out errors);
        try {
            if(hr<0 || code==null) {
                string msg="HLSL compile failed 0x"+hr.ToString("X8");
                if(errors!=null) {
                    int n=checked((int)errors.GetBufferSize().ToUInt64());
                    if(n>0) msg+=Environment.NewLine+Marshal.PtrToStringAnsi(errors.GetBufferPointer(),n);
                }
                throw new InvalidOperationException(msg);
            }
            int size=checked((int)code.GetBufferSize().ToUInt64());
            byte[] bytes=new byte[size];
            Marshal.Copy(code.GetBufferPointer(),bytes,0,size);
            File.WriteAllBytes(output,bytes);
        }
        finally {
            if(code!=null) Marshal.ReleaseComObject(code);
            if(errors!=null) Marshal.ReleaseComObject(errors);
        }
    }
}
'@

$pairs = @(
    @('divider-caustic.hlsl','divider-caustic.ps'),
    @('divider-caustic-detail.hlsl','divider-caustic-detail.ps'),
    @('divider-particles.hlsl','divider-particles.ps'),
    @('divider-particles-core.hlsl','divider-particles-core.ps')
)

foreach ($pair in $pairs) {
    $input = Join-Path $sourceDir $pair[0]
    $output = Join-Path $sourceDir $pair[1]
    if (-not (Test-Path -LiteralPath $input)) {
        throw ('Missing shader source: ' + $input)
    }
    [RdcShaderCompiler]::Compile($input,$output)
    Write-Host ('Compiled ' + $pair[0] + ' to ' + $pair[1])
}
