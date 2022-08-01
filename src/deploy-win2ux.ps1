<#
* Author: Roger
* Filename: deploy-win2ux.ps1

* Objectives:
    - Copies the necessary files from the Windows to the Unix environment
    - Starts the remote execution of the Unix environment script

* Requirements:
	- PSPC e Powershell available on the Windows environment

* Usage:
    - deploy-win2ux.ps1 -host [host] -user [user] -password [password] -path [path]

*[revision - 20220713.01 - roger ]
    - Initial version
#>




function Start-Main() {
    [CmdletBinding()]
    [OutputType([int])] #Pode representar o exitcode do PS host process
    Param(
        # Ambiente de opera��o deste script(produ��o, depura��o, homologa��o == Desenvolvimento, etc)
        [Parameter(Position = 0, Mandatory = $false)]
        [RuntimeEnvs]
        $RunEnvironment = [RuntimeEnvs]::AutoEnv
    )
    begin { }
    process {
        Initialize-Env -EnvironmentType $RunEnvironment
        #Chamado ap�s Initialize-Env para exibi��o ser capaz de exibir as diferen�as
        Show-Usage

        #todo comece a encher linguica aqui
        pscp testando.sh admin@10.12.37.%oii%:/home

        ssh admin@10.12.37.%oii% bash /home/testando.sh 

        return 0  #default = sucess
    }
    end { }
}


<#
-------------------------------------------------------------------------------------------------------
**********************************  Ponto de Entrada   ************************************************
-------------------------------------------------------------------------------------------------------
#>
try {
    $LASTEXITCODE = Start-Main -EnvironmentName dev
} catch {
    #ERROR_PROCESS_ABORTED = 1067
    $LASTEXITCODE = 1067  #Start-Main DEVE informar que tudo ocorreu normalmente por contrato
}
if ( $Script:ExecEnv -ne [RuntimeEnvs]::DbgEnv ) {
    [Environment]::Exit( $LASTEXITCODE ) #!Linha cr�tica para retorno correto
} else {
    if ($LASTEXITCODE -eq 0 ) {
        Write-Host 'Opera��o finalizada com sucesso!!!'	
    } else {
        Write-Error "Retorno da opera��o = $LASTEXITCODE"	
    }
}