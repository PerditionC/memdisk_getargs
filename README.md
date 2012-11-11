getargs
=======

Public domain tool to fetch the load arguments of a MEMDISK
(virtual disk, created by SYSLINUX MEMDISK tool in int 15h
memory space after booting with SYSLINUX / ISOLINUX / ...
to simplyfy booting non-Linux operating systems). Based
on the IFMEMDSK tool. Original getargs by Eric Auer.

This version will also skip FreeDOS kernel config.sys lines.  
I.e. the original getargs will turn {ECHO hi} into 
@SET {ECHO=1 
@SET hi}=1 
but this version will omit them.

See also docs/memdisk.txt in fdkernel repository.

Use NASM to build.  nasm -DMAGIC getargs.asm -o getargs.com

Nov 2012
Kenneth J. Davis
