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
; 1 = read, 0 = write
; code for later, as we will likely need to switch our pins between input and output:
; (port and pin numbers are placeholders pins not typically enabled for I2C module use)
; setting pins as output:
; bis.w   #LOCKLPM5,&PM5CTL0 
; bis.b   #0b00001100, &P1DIR
; bis.b   #0b00001100, &P1OUT  (passively high)
; bic.w   #LOCKLPM5,&PM5CTL0 

setting pins as input:
; bis.w   #LOCKLPM5,&PM5CTL0 
; bic.b   #0b00001100, &P3DIR
; bis.b   #0b00001100, &P3REN
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

init: 
            ; switches
            bic.b   #0b001000, &P2DIR ; switch 2
            bis.b   #0b001000, &P2REN
            bic.b   #0b001000, &P2OUT  (pull down resistors, for now)


            bic.b   #0b000010, &P4DIR ; switch 1
            bis.b   #0b000010, &P4REN
            bic.b   #0b000010, &P4OUT  (pull down resistors, for now)
            bic.b   #0b000010, &P4IES
            bic.b   #0b000010, &P4IFG
            bis.b   #0b000010, &P4IE

            bic.w   #0b00001100, &SEL0       ; re-affirm default setting
            bic.w   #0b00001100, &SEL1       ; re-affirm default setting
            NOP
            bis.w   #GIE, SR                ; enable global interrupts
            NOP

            bic.w   #LOCKLPM5,&PM5CTL0       ; Unlock I/O pins
            
            mov.w   #68, R6

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
; ---------- Switch1_ISR -------- 
Switch1_ISR:
            bic.b    #BIT2, P3OUT
            mov.w    #100, R5
wait:
            dec.w    R5
            jnz wait
Send_data_start:
            mov.b    R6, R7
            mov.b    #7, R9
            ; BSL R7
Send_data:
            ; is "send next bit" bit toggled to 1?, if no, jump to Send_data
            ; otherwise, BSL and change pin (3.3) value to shifted-out bit
            ; decrement bit-send counter (R9)
            ; jnz send_data
Clear_SW1_Flag:
             bic.b    #BIT1, P4IFG
             reti       



; ------ end Switch1_ISR ----------

ISR_Clock:
        ; set clock pin to high 
        ; is data being sent (is send register (R7) empty (0))
        ; if no, then jump to switch_clock
Clear_clock_flag:
        ; clear flag
        ; reti

Switch_clock:
        ; toggle clock output
        ; if bit was toggled to low, toggle "send next bit" bit to 1 (jump to new subroutine to perform this operation, =>
                ; => then jump to Clear_clock_flag)
        ; jump to clear clock flag

;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   RESET_VECTOR            ; MSP430 RESET Vector
            .short  RESET                   ;

            .sect   ".int43"
            .short  ISR_HeartBeat

            .sect   ".int22"
            .short  Switch1_ISR



; switch 1 is pressed:
; 1. SDA (P3.2) moves low
; 2. wait 1/10,000 of a second
; 3. begin clock operations (move data to send register)
; 4. clock moves low (passive)
; 5. send first bit of data (address)
; 6. clock moves high, then low
; 7. repeat steps 5-6 six more times