-- update, delete, copy, merge e truncate contam como escrita tanto quanto insert.
update public.aluno set status = 'ATIVO' where conferido;
delete from public.combo where ativo is false;
truncate table public.movimento_estoque;
copy public.material (codigo, nome) from stdin;
