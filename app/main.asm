;-------------------------------------------------------------------------------
; Include files
            .cdecls C,LIST,"msp430.h"  ; Include device header file
;-------------------------------------------------------------------------------

            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.

            .global __STACK_END
            .sect   .stack                  ; Make stack linker segment ?known?

            .text                           ; Assemble to Flash memory
            .retain                         ; Ensure current section gets linked
            .retainrefs

RESET       mov.w   #__STACK_END,SP         ; Initialize stack pointer
StopWDT     mov.w   #WDTPW+WDTHOLD,&WDTCTL  ; Stop WDT
; code for later, as we will likely need to switch our pins between input and output:
; (port and pin numbers are placeholders pins not typically enabled for I2C module use)
; setting pins as output:
; bis.w   #LOCKLPM5,&PM5CTL0 
; bis.b   #0b00001100, &P1DIR
; bis.b   #0b00001100, &P1OUT  (passively high)
; bic.w   #LOCKLPM5,&PM5CTL0 

setting pins as input:
; bis.w   #LOCKLPM5,&PM5CTL0 
; bic.b   #0b00001100, &P1DIR
; bis.b   #0b00001100, &P1REN
; bic.b   #0b00001100, &P1OUT  (pull down resistors, for now)
; bic.w   #LOCKLPM5,&PM5CTL0 



init_heartbeat:
            bic.b   #BIT0,&P1OUT            ; Clear P1.0 output
            bis.b   #BIT0,&P1DIR            ; P1.0 output

            bis.w   #TBCLR, &TB0CTL         ; 
            bis.w   #TBSSEL__ACLK, &TB0CTL  ; choose ACLK
            bis.w   #MC__UP, &TB0CTL        ; choose UP counting

            mov.w   #32778, &TB0CCR0        ; count to 32778 (1 second), no dividers needed
            bis.w   #CCIE, &TB0CCTL0        ; enable interrput on TB0CCTL0
            bic.w   #CCIFG, &TB0CCTL0       ; clear interrupt flag

            NOP
            bis.w   #GIE, SR                ; enable global interrupts
            NOP

            bic.w   #LOCKLPM5,&PM5CTL0       ; Unlock I/O pins
init: 
            bic.w   #0b00001100, &SEL0       ; re-affirm default setting
            bic.w   #0b00001100, &SEL1       ; re-affirm default setting
main:

            nop 
            jmp main
            nop
start:
            
stop:
            
tx_ack:
rx_ack:
tx_byte:
rx_byte:
sda_delay:
scl_delay:
send_address:
write:
read:
;------------------------------------------------------------------------------
;           Interrupt Service routines
;------------------------------------------------------------------------------
;---------- ISR_HeartBeat ------- 
ISR_HeartBeat:
        xor.b   #BIT0, &P1OUT      ; on interrupt, toggle green led
        bic.w   #CCIFG, &TB0CCTL0  ; clear interrupt flag
        reti                       ; return to code location prior to interrupt commands
;---------- End ISR_HeartBeat ------- 

;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   RESET_VECTOR            ; MSP430 RESET Vector
            .short  RESET                   ;

            .sect   ".int43"
            .short  ISR_HeartBeat