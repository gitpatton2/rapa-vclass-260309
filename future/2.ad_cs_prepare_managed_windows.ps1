# [설정] 대상 인증서 주체 이름
$TargetCertSubject = "dc.vclass.local"

# 1. WinRM 서비스 상태 확인 및 시작
Write-Host "1. WinRM 서비스 상태를 확인하고 시작합니다..."
If ((Get-Service WinRM).Status -ne 'Running') {
    Start-Service WinRM
}
Set-Service WinRM -StartupType Automatic

# 2. 로컬 저장소에서 dc.vclass.local 인증서 검색 (핵심 수정 사항)
Write-Host "2. 로컬 인증서 저장소에서 '$TargetCertSubject' 인증서를 검색합니다..."
$Cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { 
    $_.Subject -match $TargetCertSubject -or $_.DnsNameList.Unicode -contains $TargetCertSubject
} | Select-Object -First 1

if ($null -eq $Cert) {
    Write-Error "오류: '$TargetCertSubject' 인증서를 찾을 수 없습니다. 인증서가 '로컬 컴퓨터 > 개인' 저장소에 있는지 확인하십시오."
    exit 1
}
$Thumbprint = $Cert.Thumbprint
Write-Host "인증서 발견 (Thumbprint: $Thumbprint)"

# 3. 기존 WinRM HTTPS 리스너 제거 및 신규 등록
Write-Host "3. WinRM HTTPS 리스너를 재설정합니다..."
Get-ChildItem wsman:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path WSMan:\LocalHost\Listener -Address * -Transport HTTPS -HostName $TargetCertSubject -CertificateThumbPrint $Thumbprint -Force

# 4. Ansible 연결을 위한 WinRM 인증 방식 설정 (기존 스크립트 누락 방지)
Write-Host "4. WinRM 인증 및 서비스 설정을 구성합니다..."
Set-Item -Path "WSMan:\LocalHost\Service\Auth\Basic" -Value $true
Set-Item -Path "WSMan:\LocalHost\Service\Auth\CredSSP" -Value $true
Set-Item -Path "WSMan:\LocalHost\Service\AllowUnencrypted" -Value $false

# 5. 방화벽 규칙 설정 (5986 포트 허용)
Write-Host "5. 방화벽 규칙(HTTPS 5986)을 설정합니다..."
if (!(Get-NetFirewallRule -Name "WinRM-HTTPS-In" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -Name "WinRM-HTTPS-In" -Profile Any -LocalPort 5986 -Protocol TCP -Action Allow
}

Write-Host "설정이 완료되었습니다. 이제 Ansible에서 HTTPS를 통해 이 노드에 연결할 수 있습니다."
