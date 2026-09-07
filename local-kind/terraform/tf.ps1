# Wrapper para rodar o Terraform com um PATH do Windows saudável.
#
# Necessário porque, quando o terminal (ex.: terminal integrado do VS Code) é
# aberto a partir do Git Bash, o PATH herdado fica em formato POSIX
# (/c/Windows/System32) que o Windows nao consegue resolver. Nesse caso o
# provisioner local-exec do Terraform falha com:
#   exec: "cmd": executable file not found in %PATH%
#
# Este script reconstroi o PATH a partir do registro (Machine + User), que esta
# integro, e entao repassa todos os argumentos para o terraform.
#
# Uso:
#   .\tf.ps1 apply
#   .\tf.ps1 plan
#   .\tf.ps1 destroy

$rawPath = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
           [Environment]::GetEnvironmentVariable('Path', 'User')

# Limpa cada entrada: expande %VAR%, remove espacos nas bordas e entradas vazias,
# e deduplica. Necessario porque o PATH do registro tem entradas com espaco a
# esquerda (ex.: " C:\Windows\system32"). PowerShell/cmd toleram o espaco, mas o
# exec.LookPath do Go (usado pelo provisioner local-exec do Terraform) nao faz
# trim e procura o binario dentro do diretorio literal com espaco -> falha com:
#   exec: "cmd": executable file not found in %PATH%
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$clean = $rawPath -split ';' |
    ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).Trim() } |
    Where-Object { $_ -ne '' -and $seen.Add($_) }

$env:PATH = $clean -join ';'

Set-Location -Path $PSScriptRoot
& terraform @args
exit $LASTEXITCODE
