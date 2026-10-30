
/* Define memory regions. */
MEMORY
{
/* Ends at 0x08020000: flash sector 5 (128K) is kept free for 48K bankswitched games (see main.c GAME48_FLASH_BASE) */
rom (rx) : ORIGIN = 0x08000000, LENGTH = 128K
ram (rwx) : ORIGIN = 0x20000400, LENGTH = 127K
}
/* Include the common ld script. */
INCLUDE cortex-m-generic.ld

SECTIONS {
    .text : {

        /* ... */

        menu_start = .;
        INCLUDE "menu.ld" ;
        menu_end = .;

       /* ... */
    }
}

