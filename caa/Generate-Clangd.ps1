# Generate-Clangd.ps1  (caa.nvim 同梱)
# CAAワークスペースを走査して clangd 用の .clangd (ワークスペースルート) を再生成する。
# nvim からは :CaaClangd (<leader>mc) 経由で -Workspace 付きで呼ばれる。
#
# 情報源 (優先順):
#   1. WS内のフレームワーク/モジュール構造の走査 (vcxproj が古くても追従)
#   2. RADE (Native Apps IDE) が ToolsData\VisualStudio* に生成した .vcxproj の
#      AdditionalIncludeDirectories — IdentityCard から計算された prereq 閉包を
#      mkmk と同じ順序で持つ公式の IntelliSense 供給物 (CAAStudio\wxpug0401.htm)
#   3. <FW>\ImportedInterfaces\win_b64 — mkGetPreq の間接参照スタブ
#      ("indirections into the external headers", CAABtlMkFiles.htm)。
#      vcxproj が古い場合の取りこぼしを最後に拾う保険
#   4. vcxproj が1つも無い場合のみ Install_config_<os> の prereq ルート全FWを追加
#
# モジュール追加・mkGetPreq 再実行・Generate Intellisense 後に実行し直すこと。
#
#   pwsh -File Generate-Clangd.ps1 [-Workspace <CAAワークスペースルート>]
#   (省略時はカレントディレクトリをワークスペースとみなす)

param(
    [string]$Workspace = (Get-Location).Path
)

$ws = (Resolve-Path $Workspace).Path
$os = 'win_b64'
$inc = [System.Collections.Generic.List[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$modules = @()

function Add-IncDir([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return }
    $p = ($p -replace '\\\.\\', '\').TrimEnd('\')
    if ((Test-Path $p -PathType Container) -and $seen.Add($p)) { $script:inc.Add($p) }
}

# --- 1. WS内 (IdentityCard を持つディレクトリをフレームワークとみなす)
$frameworks = @(Get-ChildItem $ws -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'IdentityCard')
})
if ($frameworks.Count -eq 0) {
    Write-Error "CAAワークスペースではない: $ws (IdentityCard を持つフレームワークが見つからない)"
    exit 1
}
foreach ($fw in $frameworks) {
    foreach ($m in Get-ChildItem $fw.FullName -Directory -Filter '*.m') {
        Add-IncDir (Join-Path $m.FullName 'LocalInterfaces')
        Add-IncDir (Join-Path $m.FullName 'include')
        Add-IncDir (Join-Path $m.FullName "LocalGenerated\$os")
        # mkmk は「ヘッダ所有モジュールの処理時に __<modulename> を定義する」
        # (公式: CAABtlMANPrereq.htm)。ExportedByXxx の dllexport/import 切替が
        # これに依存するため、ルート .clangd 末尾の If: PathMatch フラグメントで再現する
        $script:modules += $m
    }
    foreach ($d in 'PrivateInterfaces', 'ProtectedInterfaces', 'PublicInterfaces') {
        Add-IncDir (Join-Path $fw.FullName $d)
    }
    foreach ($g in 'PrivateGenerated', 'ProtectedGenerated', 'PublicGenerated') {
        Add-IncDir (Join-Path $fw.FullName "$g\$os")
    }
}

# --- 2. prereq: RADE生成 vcxproj の AdditionalIncludeDirectories を順序維持で統合
$vcxprojs = @(Get-ChildItem (Join-Path $ws 'ToolsData') -Recurse -Filter '*.vcxproj' -ErrorAction SilentlyContinue)
foreach ($proj in $vcxprojs) {
    try { $xml = [xml](Get-Content $proj.FullName -Raw) } catch { continue }
    $dirLists = @($xml.Project.ItemDefinitionGroup.ClCompile.AdditionalIncludeDirectories | Where-Object { $_ })
    if (-not $dirLists) { continue }  # 中身が空の vcxproj (生成事故) はスキップ
    foreach ($d in ($dirLists[0] -split ';')) {  # 構成(Debug/Release)間で同一なので先頭のみ
        if ($d -notmatch '^%\(') { Add-IncDir $d }
    }
}

# --- 3. 保険: mkGetPreq の間接参照スタブ (必ず最後に置く)
foreach ($fw in $frameworks) {
    Add-IncDir (Join-Path $fw.FullName "ImportedInterfaces\$os")
}

# --- 4. 保険2: vcxproj が無いWSでは Install_config の prereq ルートを総当たり
if ($vcxprojs.Count -eq 0) {
    $installConfig = Join-Path $ws "Install_config_$os"
    if (Test-Path $installConfig) {
        $preqRoots = (Get-Content $installConfig)[1] -split ';' | Where-Object { $_ }
        foreach ($root in $preqRoots) {
            if (-not (Test-Path $root)) { continue }
            foreach ($fw in Get-ChildItem $root -Directory) {
                Add-IncDir (Join-Path $fw.FullName 'PublicInterfaces')
                Add-IncDir (Join-Path $fw.FullName "PublicGenerated\$os")
            }
        }
    }
}

# 定義の出典:
#   _WINDOWS_SOURCE      : mkmk が Windows で /D 定義 (公式: CAABtlMANPrereq.htm)
#   _ALLOW_KEYWORD_MACROS: RADE生成 vcxproj の PreprocessorDefinitions 実物より
#   _LANGUAGE_CPLUSPLUS  : 非文書化だが CATDlgUtility.h 等の Dialog 系ヘッダが
#                          本体を丸ごとこのガードで囲っており、実ビルドでは定義される前提
#   _MFC_VER=0x0800      : CATSysDataType.h 等が「MFC 8以上なら素のWindows SDKヘッダ、
#                          未定義なら afxwin.h (要MFCインストール)」と分岐するため、
#                          MFC非搭載のVS2022でも afxwin.h を回避できる値を与える
# UNICODE/_UNICODE: WS内ソースが #ifdef UNICODE で wchar_t 分岐を書いており (例:
# DGITdeHV6WebServiceAccess.cpp の STARTUPINFOW 初期化)、cl での実ビルドが通っている
# 以上、実ビルド環境では定義されている
# CAT_ENABLE_NATIVE_EXCEPTION: CATErrorMacros.h は NATIVE_EXCEPTION 無効時に
# try/catch/throw キーワードを「#define try ERROR」等で潰す (L228-236)。この定義で
# 再定義ブロックだけを回避する (json.hpp 等の例外使用コードが即死するのを防ぐ)
# /EHsc は mkmk 既定 (例外OFF, CXX_EXCEPTION) と異なるが、MSVC STL のパース用に付与
$flags = @('/EHsc', '/std:c++17',
           '-D_WINDOWS_SOURCE', '-D_ALLOW_KEYWORD_MACROS', '-D_LANGUAGE_CPLUSPLUS',
           '-D_MFC_VER=0x0800', '-DUNICODE', '-D_UNICODE',
           '-DCAT_ENABLE_NATIVE_EXCEPTION') +
         ($inc | ForEach-Object { "-I$($_ -replace '\\', '/')" })

$lines = @('# caa.nvim の Generate-Clangd.ps1 により生成。手動編集しない (再生成で上書きされる)',
           'CompileFlags:', '  Compiler: clang-cl', '  Add:')
$lines += $flags | ForEach-Object { "    - `"$_`"" }

# モジュール別フラグメント: 対象モジュール配下のファイルにだけ __<modulename> を定義
foreach ($m in $modules) {
    $modName = $m.Name -replace '\.m$', ''
    $lines += '---'
    $lines += 'If:'
    $lines += "  PathMatch: .*/$($m.Name -replace '\.', '\.')/.*"
    $lines += 'CompileFlags:'
    $lines += '  Add:'
    $lines += "    - `"-D__$modName`""
}

Set-Content -Path (Join-Path $ws '.clangd') -Value ($lines -join "`n") -Encoding utf8NoBOM
Write-Host ".clangd generated: $($inc.Count) include dirs (vcxproj: $($vcxprojs.Count), modules: $($modules.Count))"
