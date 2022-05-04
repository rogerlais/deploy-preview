echo off
set /p nome=Digite o nome do Script:
set /p ip=Digite IP:

pscp %nome%.sh admin@%ip%:/home

ssh admin@%ip% bash /home/%nome%.sh 

pause