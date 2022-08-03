echo off
set /p nome=Digite o nome do Script:
set /p ip=Digite IP:


REM !!!!! Obsolete way, use deploy-win2ux.ps1 instead !!!!!

pscp %nome%.sh admin@%ip%:/home

ssh admin@%ip% bash /home/%nome%.sh 

pause